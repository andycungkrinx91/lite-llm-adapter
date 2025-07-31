import json
import logging
import uuid
from fastapi import APIRouter, Depends, HTTPException, status
from sse_starlette.sse import EventSourceResponse
import redis.asyncio as redis

from models.model_loader import get_model, MODEL_CONFIGS, FAILED_MODELS
from dependencies import get_app_config, AppConfig, verify_api_key, get_redis_client
from services.concurrency_manager import RedisQueueSlot
from schemas.openai_types import ChatCompletionRequest

logger = logging.getLogger(__name__)

router = APIRouter()

@router.get("/v1/models", tags=["Models"])
async def list_models(_: dict = Depends(verify_api_key)):
    """Lists the currently available models."""
    return {
        "object": "list",
        "data": [{"id": model_id, "object": "model", "owned_by": "user"} for model_id in MODEL_CONFIGS.keys()],
    }

@router.post("/v1/chat/completions", tags=["Chat"])
async def create_chat_completion(
    request: ChatCompletionRequest,
    redis_client: redis.Redis = Depends(get_redis_client),
    app_config: AppConfig = Depends(get_app_config),
    _auth: dict = Depends(verify_api_key)
):
    """
    Creates a model response for the given chat conversation.
    This endpoint uses Redis for queuing and session management.
    """
    model_id = request.model or app_config.DEFAULT_MODEL_ID

    # --- Case-Insensitive Model Lookup ---
    # Find the correct model ID by performing a case-insensitive search.
    # This improves usability as users might not match the exact case.
    found_model_id = None
    for available_id in MODEL_CONFIGS.keys():
        if available_id.lower() == model_id.lower():
            found_model_id = available_id
            break

    # Case 1: The requested model ID does not match any configuration.
    if not found_model_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Model '{model_id}' not found. Available models: {list(MODEL_CONFIGS.keys())}",
        )

    # Case 2: The model is configured but failed to load (e.g., file missing, config error).
    # This is a server-side issue, so a 500-level error is appropriate.
    if found_model_id in FAILED_MODELS:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Model '{found_model_id}' is configured but failed to load. Reason: {FAILED_MODELS[found_model_id]}. Please check server logs and ensure the model file is correctly placed.",
        )

    llm = await get_model(found_model_id, app_config)
    model_config = MODEL_CONFIGS.get(found_model_id)

    # Case 3: The model is configured and didn't fail, but is still not available.
    # This indicates a logical error in the application startup.
    if not llm:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Model '{found_model_id}' is configured but could not be retrieved. This indicates a server-side inconsistency. Please check the logs.",
        )

    # --- Session Management ---
    # If a session_id is provided, continue the conversation. Otherwise, start a new one.
    session_id = request.session_id or str(uuid.uuid4())
    session_key = f"{app_config.REDIS_KEY_PREFIX}:session:{session_id}"
    try:
        history_json = await redis_client.get(session_key)
        history = json.loads(history_json) if history_json else []
    except Exception as e:
        logger.error(f"Failed to retrieve session history for {session_key}: {e}")
        history = []

    # Combine historical messages with the new ones
    incoming_messages = [msg.model_dump() for msg in request.messages]
    messages_as_dicts = history + incoming_messages

    # --- System Prompt Injection ---
    # Intelligently inject the model's default system prompt if needed.
    default_system_prompt = model_config.get("system_prompt")

    # Check if the user has already provided a system prompt.
    # The OpenAI standard is for the system message to be the first in the list.
    user_provided_system_prompt = False
    if messages_as_dicts and messages_as_dicts[0].get("role") == "system":
        user_provided_system_prompt = True

    # Inject the default prompt only if one is defined for the model AND
    # the user has not supplied their own. This ensures user-provided prompts
    # always take precedence.
    if default_system_prompt and not user_provided_system_prompt:
        messages_as_dicts.insert(0, {"role": "system", "content": default_system_prompt})

    # --- Parameter Extraction ---
    # Extract generation parameters from the request. The LocalLLM service will handle
    # merging these with the model's own default parameters.
    request_params = request.model_dump(exclude_unset=True, exclude={"model", "messages", "stream", "session_id"})
    
    # Use the context manager to handle acquiring and releasing the processing slot.
    # This simplifies the code and ensures the slot is always returned.
    async with RedisQueueSlot(redis_client, app_config, found_model_id):
        if request.stream:
            async def stream_generator():
                try:
                    response_generator = llm.create_chat_completion(
                        messages=messages_as_dicts, stream=True, **request_params
                    )
                    
                    first_chunk = True
                    full_response_content = ""

                    for chunk in response_generator:
                        # The first chunk from the model is special. We inject the session_id
                        # into it. This ensures the client receives the session_id without
                        # breaking the OpenAI streaming protocol, as every yielded object
                        # is a valid chat completion chunk.
                        if first_chunk:
                            chunk['session_id'] = session_id
                            first_chunk = False

                        delta = chunk.get("choices", [{}])[0].get("delta", {})
                        if "content" in delta:
                            full_response_content += delta.get("content", "")
                        yield json.dumps(chunk)

                    # After the stream is finished, update the session history in Redis
                    if full_response_content:
                        assistant_message = {"role": "assistant", "content": full_response_content}
                        updated_history = messages_as_dicts + [assistant_message]
                        await redis_client.set(session_key, json.dumps(updated_history), ex=3600) # 1-hour expiry

                except Exception as e:
                    logger.error(f"Error during model generation stream: {e}", exc_info=True)
                    # Provide a more detailed error message to the client for easier debugging.
                    error_message = f"An error occurred during stream generation: {str(e)}"
                    error_payload = {"error": {"message": error_message}}
                    yield json.dumps(error_payload)

            return EventSourceResponse(stream_generator(), media_type="text/event-stream")
        
        # Non-streaming logic
        try:
            response = llm.create_chat_completion(
                messages=messages_as_dicts, stream=False, **request_params
            )

            # Update session history in Redis
            assistant_message = response["choices"][0]["message"]
            updated_history = messages_as_dicts + [assistant_message]
            await redis_client.set(session_key, json.dumps(updated_history), ex=3600) # 1-hour expiry

            # Add session_id to the final response
            response['session_id'] = session_id
            return response

        except Exception as e:
            logger.error(f"Error during model generation for model '{model_id}': {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"An error occurred during model generation: {e}"
            )
