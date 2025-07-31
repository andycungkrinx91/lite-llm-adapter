import logging
from typing import Optional
import redis.asyncio as redis
from fastapi import HTTPException, status
from dependencies import AppConfig

logger = logging.getLogger(__name__)

class RedisQueueSlot:
    """
    An async context manager to safely acquire and release a processing slot from a Redis queue.
    This ensures that even if an error occurs during processing, the slot is always returned.
    """
    def __init__(self, redis_client: redis.Redis, app_config: AppConfig, model_id: str):
        self.redis_client = redis_client
        self.queue_key = f"{app_config.REDIS_KEY_PREFIX}:processing_slots"
        self.max_requests = app_config.MAX_CONCURRENT_REQUESTS
        self.model_id = model_id
        self.slot: Optional[bytes] = None

    async def __aenter__(self):
        # Only use the queue if it's enabled (max_requests > 0)
        if self.max_requests <= 0:
            return

        logger.info(f"Request for model '{self.model_id}' is waiting for a processing slot...")
        try:
            self.slot = await self.redis_client.blpop(self.queue_key, timeout=120)
        except Exception as e:
            logger.error(f"Redis blpop command failed: {e}", exc_info=True)
            raise HTTPException(status_code=503, detail="Could not connect to request queue.")
        
        if self.slot is None:
            raise HTTPException(status_code=503, detail="All processing slots are busy; request timed out.")
        
        logger.info(f"Processing slot acquired for model '{self.model_id}'. Starting generation.")

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        # Always return the processing slot to the queue if it was acquired.
        if self.slot:
            await self.redis_client.rpush(self.queue_key, "1")
            logger.info(f"Processing slot for model '{self.model_id}' returned to queue.")
