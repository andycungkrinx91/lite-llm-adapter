import json
import os
from typing import Dict, Optional, Any

from services.local_llm import LocalLLM
from dependencies import AppConfig

# MODEL_CONFIGS stores the raw configuration dictionaries from the JSON file.
MODEL_CONFIGS: Dict[str, Any] = {}
# LLM_INSTANCES stores the actual, loaded LocalLLM objects.
LLM_INSTANCES: Dict[str, LocalLLM] = {}
# FAILED_MODELS stores models that were configured but failed to load, with the reason.
FAILED_MODELS: Dict[str, str] = {}

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
    default_params = {}
    try:
        with open(defaults_path, 'r') as f:
            default_params = json.load(f).get("default_params", {})
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

    for model_config in model_configs:
        model_id = model_config.get("id")
        model_type = model_config.get("model_type")

        if not model_id:
            print("Skipping model config due to missing 'id'.")
            continue
        
        print(f"Loading model '{model_id}'...")
        if model_type == 'local_gguf' or model_type == 'local':
            relative_path = model_config.get("path") # Get the filename from config
            if not relative_path:
                reason = "Configuration is missing the 'path' attribute for the model file."
                print(f"Warning: {reason} for model '{model_id}'. Skipping.")
                FAILED_MODELS[model_id] = reason
                continue

            model_path = os.path.join(app_config.MODEL_BASE_PATH, relative_path) # Construct full path
            if not os.path.exists(model_path):
                reason = f"Model file not found at path: {model_path}"
                print(f"Warning: {reason} for model '{model_id}'. Skipping.")
                FAILED_MODELS[model_id] = reason
                continue
            
            # Start with default params, then merge model-specific params
            params = default_params.copy()
            model_specific_params = model_config.get("params", {})
            params.update(model_specific_params)

            # Only set chat_format if it's explicitly defined in the config.
            # Otherwise, let llama-cpp-python auto-detect it from the GGUF metadata.
            if "chat_format" in model_config:
                params["chat_format"] = model_config["chat_format"]

            params["n_threads"] = app_config.CPU_THREADS

            try:
                LLM_INSTANCES[model_id] = LocalLLM(
                    model_path=model_path,
                    model_id=model_id,
                    params=params
                )
                print(f"Successfully loaded local model: {model_id}")
            except Exception as e:
                reason = f"Error during initialization: {e}"
                print(f"Error loading local model '{model_id}': {reason}")
                FAILED_MODELS[model_id] = reason

        # Add logic for other model types (OpenAI, Google) here if needed
        # elif model_type == 'openai':
        #     MODELS[model_id] = OpenAIModel(...)

        else:
            print(f"Warning: Unknown model_type '{model_type}' for model '{model_id}'. Skipping.")

def get_model(model_id: str) -> Optional[Any]:
    """Retrieves a loaded model instance by its ID."""
    return LLM_INSTANCES.get(model_id)