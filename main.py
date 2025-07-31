from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, HTTPException, status
import redis.asyncio as redis

# Imports from our project files
from models.model_loader import load_models, FAILED_MODELS
from routers import chat
from dependencies import get_app_config

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Manages application startup and shutdown events.
    """
    # --- Code to run on STARTUP ---
    print("💡 Application starting up...")
    
    # Get application config (which loads .env)
    app_config = get_app_config()
    app.state.config = app_config
    
    # Pre-load all configured GGUF models into memory, passing the config
    load_models(app_config)

    # After loading, check if any models failed and print a clear, actionable warning.
    if FAILED_MODELS:
        print("\n" + "="*80)
        print("⚠️ WARNING: Some configured models failed to load.")
        print("This is often because the GGUF model file is missing or misplaced.")
        print("Please check the following:")
        print("  1. Have you run the './models-downloader.sh' script?")
        print("  2. Are the model files located in the volume-mounted directory?")
        print("-" * 80)
        for model_id, reason in FAILED_MODELS.items():
            print(f"  - Model: '{model_id}'")
            print(f"    Reason: {reason}")
        print("="*80 + "\n")

    # Add a hard failure check for the default model. This is a critical failure.
    if app_config.DEFAULT_MODEL_ID in FAILED_MODELS:
        default_model_id = app_config.DEFAULT_MODEL_ID
        reason = FAILED_MODELS[default_model_id]
        error_message = (
            f"\n{'='*80}\n"
            f"FATAL: The default model '{default_model_id}' configured in your .env file failed to load.\n"
            f"Reason: {reason}\nThe application cannot start without its default model.\n"
            f"Please run './models-downloader.sh' and ensure the file is correctly placed.\n"
            f"{'='*80}\n"
        )
        raise RuntimeError(error_message)
    
    # Establish and verify the connection to Redis
    try:
        app.state.redis_client = redis.from_url(app_config.REDIS_URL, decode_responses=True)
        redis_client = app.state.redis_client
        await redis_client.ping()
        print("Successfully connected to Redis.")

        # Initialize the concurrency queue with available processing slots
        queue_key = "llm_processing_slots"
        max_requests = app_config.MAX_CONCURRENT_REQUESTS
        await redis_client.delete(queue_key) # Clear any old state on restart
        if max_requests > 0:
            pipeline = redis_client.pipeline()
            for _ in range(max_requests):
                pipeline.rpush(queue_key, "1")
            await pipeline.execute()
        print(f"Initialized Redis concurrency queue '{queue_key}' with {max_requests} slots.")
    except Exception as e:
        print(f"Failed to connect to Redis on startup: {e}")
        app.state.redis_client = None

    print("✅ Application startup complete.")
    
    yield  # The application is now running
    
    # --- Code to run on SHUTDOWN ---
    print("🔌 Application shutting down...")
    # Add any cleanup logic here if needed
    if hasattr(app.state, 'redis_client') and app.state.redis_client:
        await app.state.redis_client.close()
        print("Redis connection closed.")

# FastAPI application setup
app = FastAPI(
    title="Lite-LLM Adapter",
    version="1.0.0",
    description="A FastAPI backend serving local GGUF models with an OpenAI-compatible API.",
    lifespan=lifespan
)

# Include the main router for chat completions and model listing
app.include_router(chat.router)

# Add a simple health check endpoint
@app.get("/health", status_code=200, tags=["Health"])
async def health_check(request: Request):
    """
    Checks the status of the API and its dependencies (e.g., Redis).
    """
    dependencies = {}
    is_healthy = True

    # Check Redis connection
    try:
        redis_client = request.app.state.redis_client
        if not redis_client or not await redis_client.ping():
            raise ConnectionError("Redis ping failed")
        dependencies["redis"] = "ok"
    except Exception:
        dependencies["redis"] = "unavailable"
        is_healthy = False

    if is_healthy:
        return {"status": "ok", "dependencies": dependencies}
    else:
        # If any dependency is down, return a 503 Service Unavailable
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"status": "degraded", "dependencies": dependencies}
        )
