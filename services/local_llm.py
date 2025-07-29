import logging
from typing import Iterator, List, Dict, Any, Union

from llama_cpp import Llama

class LocalLLM:
    """
    A service class to interact with a local GGUF model using llama-cpp-python.
    """
    _logger = logging.getLogger(__name__)

    def __init__(self, model_path: str, model_id: str, params: Dict[str, Any]):
        self.model_id = model_id

        # Define keys for the Llama constructor vs. generation to separate them
        constructor_keys = {"n_ctx", "n_batch", "n_gpu_layers", "verbose", "chat_format", "n_threads"}

        # Separate llama.cpp constructor params from generation params
        llama_constructor_params = {k: v for k, v in params.items() if k in constructor_keys}
        llama_constructor_params.setdefault("verbose", True) # Ensure verbose is set
        llama_constructor_params.setdefault("n_gpu_layers", 0) # Explicitly default to CPU

        # The rest are assumed to be default generation params
        self.generation_params = {
            k: v for k, v in params.items() if k not in constructor_keys
        }

        self.model = Llama(model_path=model_path, **llama_constructor_params)

    def create_chat_completion(
        self, messages: List[Dict[str, str]], stream: bool = False, **kwargs
    ) -> Union[Iterator[Dict[str, Any]], Dict[str, Any]]:
        """
        Generates a chat completion response, either streaming or non-streaming.
        """
        try:
            # Start with the model's default generation parameters
            final_params = self.generation_params.copy()
            # Update with any user-provided parameters, which will take precedence
            final_params.update(kwargs)

            # The Llama instance now handles chat templating automatically based on the
            # chat_format provided during initialization.

            # For non-streaming requests, it's more efficient to let llama-cpp-python
            # handle the full generation and return a single object directly,
            # rather than streaming and aggregating in Python.
            if not stream:
                final_params['stream'] = False
                return self.model.create_chat_completion(messages=messages, **final_params)

            # For streaming requests, we ensure stream=True and return the generator.
            final_params['stream'] = True
            return self.model.create_chat_completion(messages=messages, **final_params)

        except Exception as e:
            self._logger.error(
                f"Error during chat completion for model '{self.model_id}': {e}",
                exc_info=True
            )
            # Re-raise the exception to be handled by the API router
            raise