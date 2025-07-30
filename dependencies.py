from fastapi import Depends, HTTPException, status, Security, Request
from functools import lru_cache
from pydantic_settings import BaseSettings
from fastapi.security import APIKeyHeader
import redis.asyncio as redis

# Use Pydantic's BaseSettings to load from .env file
class AppConfig(BaseSettings):
    ENVIRONMENT: str = "dev"
    DEFAULT_MODEL_ID: str = "qwen3-0.6b"
    MODEL_BASE_PATH: str = "/app/models/gguf_models"
    REDIS_URL: str = "redis://localhost:6379"
    CPU_THREADS: int = 4
    AUTH: str = "your-default-secret-token" # A default for safety
    MAX_CONCURRENT_REQUESTS: int = 3

    class Config:
        env_file = ".env"
        extra = "ignore"

# @lru_cache creates a singleton instance of the config
@lru_cache()
def get_app_config():
    return AppConfig()

# --- Security Dependencies ---

api_key_header = APIKeyHeader(name="Authorization", auto_error=False)

async def verify_api_key(
    api_key: str = Security(api_key_header),
    config: AppConfig = Depends(get_app_config)
):
    """Verifies the API key from the Authorization header (e.g., "Bearer <token>")."""
    if not api_key:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Authorization header is missing")
    
    # Accommodate both "Bearer <token>" and just "<token>" for better usability.
    token = api_key
    prefix = "Bearer "
    if api_key.startswith(prefix):
        token = api_key[len(prefix):]

    if token != config.AUTH:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Invalid or expired API Key")

def get_redis_client(request: Request) -> redis.Redis:
    """Dependency to get the Redis client from the application state."""
    if not hasattr(request.app.state, 'redis_client') or request.app.state.redis_client is None:
        # This will be triggered if Redis failed to connect on startup
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Redis service is not available."
        )
    return request.app.state.redis_client
