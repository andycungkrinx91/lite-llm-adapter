import json
import os
import asyncio
from functools import partial
from typing import Dict, Optional, Any

from services.local_llm import LocalLLM
from dependencies import AppConfig

# MODEL_CONFIGS stores the raw configuration dictionaries from the JSON file.
MODEL_CONFIGS: Dict[str, Any] = {}
# LLM_INSTANCES stores the actual, loaded LocalLLM objects.
LLM_INSTANCES: Dict[str, LocalLLM] = {}
# FAILED_MODELS stores models that were configured but failed to load, with the reason.
FAILED_MODELS: Dict[str, str] = {}
# MODEL_LOCKS prevents race conditions when two requests for the same new model arrive simultaneously.
MODEL_LOCKS: Dict[str, asyncio.Lock] = {}
# Store default constructor and generation parameters separately for clarity.
DEFAULT_CONSTRUCTOR_PARAMS: Dict[str, Any] = {}
DEFAULT_GENERATION_PARAMS: Dict[str, Any] = {}

def load_models(app_config: AppConfig):
    """
    Loads models from the appropriate config file (dev or prod) based on the environment.
    This function is called once at application startup.
    """
    env = app_config.ENVIRONMENT
    config_filename = f"model_config_{env}.json"
    defaults_filename = "model_config_defaults.json"
    config_path = os.path.join(os.path.dirname(__file__), config_filename)
    defaults_path = os.path.join(os.path.dirname(__file__), defaults_filename)
    
    print(f"Running in '{env}' mode. Loading models from '{config_filename}'...")

    # Load default parameters first
    global DEFAULT_CONSTRUCTOR_PARAMS, DEFAULT_GENERATION_PARAMS
    try:
        with open(defaults_path, 'r') as f:
            defaults_data = json.load(f)
            DEFAULT_CONSTRUCTOR_PARAMS = defaults_data.get("default_constructor_params", {})
            DEFAULT_GENERATION_PARAMS = defaults_data.get("default_generation_params", {})
    except FileNotFoundError:
        print(f"Info: {defaults_filename} not found. No default params will be applied.")
    except json.JSONDecodeError:
        print(f"Warning: Could not decode {defaults_filename}. Check for syntax errors.")

    try:  # Read the main environment-specific config file
        with open(config_path, 'r') as f:
            model_configs = json.load(f)
    except FileNotFoundError:
        print(f"Warning: {config_filename} not found at {config_path}. No models loaded.")
        return

    print(f"Found {len(model_configs)} model(s) in configuration.")
    # First, populate the MODEL_CONFIGS dictionary with all configurations.
    for config in model_configs:
        if "id" in config:
            MODEL_CONFIGS[config["id"]] = config

    # Pre-check configurations and create locks, but do not load models yet.
    for model_config in model_configs:
        model_id = model_config.get("id")
        if not model_id:
            print("Skipping model config due to missing 'id'.")
            continue
        
        # Create a lock for each potential model to manage on-demand loading.
        MODEL_LOCKS[model_id] = asyncio.Lock()

        # Perform an initial check to see if the model file exists.
        # This allows the API to fail fast for misconfigured models.
        relative_path = model_config.get("path")
        if not relative_path:
            FAILED_MODELS[model_id] = "Configuration is missing the 'path' attribute."
            continue
        
        model_path = os.path.join(app_config.MODEL_BASE_PATH, relative_path)
        if not os.path.exists(model_path):
            FAILED_MODELS[model_id] = f"Model file not found at path: {model_path}"

async def get_model(model_id: str, app_config: AppConfig) -> Optional[Any]:
    """
    Retrieves a model instance by its ID, loading it on-demand if it's not already in memory.
    This function is thread-safe and safe for concurrent asyncio calls.
    """
    # First, check if the instance is already loaded. This is the fast path.
    if model_id in LLM_INSTANCES:
        return LLM_INSTANCES.get(model_id)

    # If not loaded, acquire a lock specific to this model_id to prevent race conditions.
    async with MODEL_LOCKS[model_id]:
        # Double-check if another request loaded the model while we were waiting for the lock.
        if model_id in LLM_INSTANCES:
            return LLM_INSTANCES.get(model_id)

        # If we are here, it's our job to load the model.
        print(f"Model '{model_id}' not in cache. Loading on-demand...")
        model_config = MODEL_CONFIGS.get(model_id)
        model_path = os.path.join(app_config.MODEL_BASE_PATH, model_config["path"])

        # Start with global defaults, then merge model-specific params.
        # This ensures a clear hierarchy of configuration.
        params = DEFAULT_CONSTRUCTOR_PARAMS.copy()
        params.update(DEFAULT_GENERATION_PARAMS)
        params.update(model_config.get("params", {}))
        if "chat_format" in model_config:
            params["chat_format"] = model_config["chat_format"]
        params["n_threads"] = app_config.CPU_THREADS

        # The Llama() constructor is a blocking, CPU-intensive call.
        # We must run it in a thread pool to avoid blocking the main asyncio event loop.
        loop = asyncio.get_running_loop()
        llm_instance = await loop.run_in_executor(
            None, partial(LocalLLM, model_path=model_path, model_id=model_id, params=params)
        )

        LLM_INSTANCES[model_id] = llm_instance
        print(f"✅ Successfully loaded and cached model: {model_id}")
        return llm_instance