from contextlib import asynccontextmanager
from fastapi import FastAPI
import redis.asyncio as redis

# Imports from our project files
from models.model_loader import load_models
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
def health_check():
    """
    Simple endpoint to confirm the API is running.
    """
    return {"status": "ok"}
