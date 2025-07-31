#!/bin/bash

# This script downloads GGUF model files into the 'models/gguf_models/' directory.
# It downloads a minimal set for 'dev' environment and a full set for 'prod'.
#
# Usage:
#   ./models-downloader.sh        (for dev environment)
#   ./models-downloader.sh prod   (for prod environment)

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
TARGET_DIR="models/gguf_models"
ENVIRONMENT=${1:-dev} # Default to 'dev' if first argument is not provided

echo "[INFO] Running in '$ENVIRONMENT' mode."

# --- Model Definitions ---
# Start with the base models for the 'dev' environment
declare -A models=(
    ["qwen3-0.6b"]="https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf"
    ["qwen2.5-coder-0.5b"]="https://huggingface.co/unsloth/Qwen2.5-Coder-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-0.5B-Instruct-Q4_K_M.gguf"
)

# If the environment is 'prod', add the production models to the list
if [ "$ENVIRONMENT" == "prod" ]; then
    echo "[INFO] Adding production models to the download list..."
    models["gemma-3-1b"]="https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf"
    models["llama3.2-1b"]="https://huggingface.co/unsloth/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
    models["llama3.2-3b"]="https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
    models["qwen2.5-coder-3b"]="https://huggingface.co/unsloth/Qwen2.5-Coder-3B-Instruct-128K-GGUF/resolve/main/Qwen2.5-Coder-3B-Instruct-Q4_K_M.gguf"
    models["lora-qwen2.5-vl-3b"]="https://huggingface.co/mradermacher/LoRA-qwen2.5VL3b-2600-GGUF/resolve/main/LoRA-qwen2.5VL3b-2600.Q4_K_M.gguf"
    models["qwen3-4b-nyx-v1"]="https://huggingface.co/mradermacher/Qwen3-4B-Nyx-V1-GGUF/resolve/main/Qwen3-4B-Nyx-V1.Q4_K_M.gguf"
    models["qwen3-deepseek-reasoning"]="https://huggingface.co/mradermacher/qwen-3-reasoning-combination-with-deepseek-GGUF/resolve/main/qwen-3-reasoning-combination-with-deepseek.Q4_K_M.gguf"
    models["qwen2.5-vl-diagram2sql"]="https://huggingface.co/mradermacher/Qwen2.5-VL-Diagrams2SQL-v2-GGUF/resolve/main/Qwen2.5-VL-Diagrams2SQL-v2.Q4_K_M.gguf"
    models["tiny-qwen3-coder-4b"]="https://huggingface.co/mradermacher/TinyQwen3-distill-4B-coder-GGUF/resolve/main/TinyQwen3-distill-4B-coder.Q4_K_M.gguf"
    models["qwen3-zero-coder-0.8b"]="https://huggingface.co/DavidAU/Qwen3-Zero-Coder-Reasoning-0.8B-NEO-EX-GGUF/resolve/main/Qwen3-Zero-Coder-Reasoning-0.8B-NEO2-EX-D_AU-Q4_K_M-imat.gguf"
    models["deepseek-coder-1.3b"]="https://huggingface.co/TheBloke/deepseek-coder-1.3b-base-GGUF/resolve/main/deepseek-coder-1.3b-base.Q4_K_M.gguf"
    models["blitzar-coder-4b"]="https://huggingface.co/prithivMLmods/Blitzar-Coder-4B-F.1-GGUF/resolve/main/Blitzar-Coder-4B-F.1.Q4_K_M.gguf"
    models["gemma-3-4b-doc-writer"]="https://huggingface.co/mradermacher/gemma-3-4b-document-writer-GGUF/resolve/main/gemma-3-4b-document-writer.Q4_K_M.gguf"
    models["gemma-3-4b-ko-reasoning"]="https://huggingface.co/mradermacher/gemma-3-4b-it-Ko-Reasoning-GGUF/resolve/main/gemma-3-4b-it-Ko-Reasoning.Q4_K_M.gguf"
    models["llama3.2-3b-uncensored"]="https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-uncensored-GGUF/resolve/main/Llama-3.2-3B-Instruct-uncensored-Q4_K_M.gguf"
    models["llama-outetts-1b"]="https://huggingface.co/OuteAI/Llama-OuteTTS-1.0-1B-GGUF/resolve/main/Llama-OuteTTS-1.0-1B-Q4_K_M.gguf"
    models["phi4-mini"]="https://huggingface.co/unsloth/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf"
    models["phi4-mini-reasoning"]="https://huggingface.co/unsloth/Phi-4-mini-reasoning-GGUF/resolve/main/Phi-4-mini-reasoning-Q4_K_M.gguf?download=true"
    models["phi3.5-mini-instruct-uncensored"]="https://huggingface.co/bartowski/Phi-3.5-mini-instruct_Uncensored-GGUF/resolve/main/Phi-3.5-mini-instruct_Uncensored-Q4_K_M.gguf?download=true"
    models["smolvlm2-500m-video"]="https://huggingface.co/second-state/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/SmolVLM2-500M-Video-Instruct-Q4_K_M.gguf?download=true"
    models["smolvlm2-2.2b-instruct"]="https://huggingface.co/second-state/SmolVLM2-2.2B-Instruct-GGUF/resolve/main/SmolVLM2-2.2B-Instruct-Q4_K_M.gguf?download=true"
fi

# --- Main Script ---

# Ensure the target directory exists
echo "Ensuring directory '$TARGET_DIR' exists..."
mkdir -p "$TARGET_DIR"

# Loop through the array and download each model
for name in "${!models[@]}"; do
    url="${models[$name]}"
    # Sanitize URL: remove query string and URL-encoded spaces
    url_no_query="${url%%\?*}"
    url_sanitized="${url_no_query//%20/}"
    # Extract filename from the sanitized URL
    filename=$(basename "$url_sanitized")
    # Define the full output path
    output_path="$TARGET_DIR/$filename"
    
    echo "--- Checking model: $name ---"

    if [ -f "$output_path" ]; then
        echo "✅ Model already exists at $output_path. Skipping download."
    else
        echo "Downloading model: $name..."
        # Use the original URL for wget, but save to the sanitized filename
        wget -q --show-progress --content-disposition -O "$output_path" "$url_sanitized"
        echo "✅ Finished downloading to $output_path"
    fi
    echo ""
done
echo "All downloads complete."