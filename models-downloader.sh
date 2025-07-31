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
    models["gemma-3-12b"]="https://huggingface.co/unsloth/gemma-3-12b-it-GGUF/resolve/main/gemma-3-12b-it-Q4_K_M.gguf"
    models["qwen3-8b"]="https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-UD-Q4_K_M.gguf"
    models["qwen3-14b"]="https://huggingface.co/unsloth/Qwen3-14B-GGUF/resolve/main/Qwen3-14B-UD-Q4_K_M.gguf"
    models["deepseek-r1-qwen3-8b"]="https://huggingface.co/unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF/resolve/main/DeepSeek-R1-0528-Qwen3-8B-Q4_K_M.gguf"
    models["deepseek-r1-llama-8b"]="https://huggingface.co/unsloth/DeepSeek-R1-Distill-Llama-8B-GGUF/resolve/main/DeepSeek-R1-Distill-Llama-8B-UD-Q4_K_M.gguf"
    models["phi4-mini"]="https://huggingface.co/unsloth/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf"
    models["phi4-mini-reasoning"]="https://huggingface.co/unsloth/Phi-4-mini-reasoning-GGUF/resolve/main/Phi-4-mini-reasoning-UD-Q4_K_M.gguf"
    models["llama3.2-3b"]="https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-UD-Q4_K_M.gguf"
    models["llama3.1-8b"]="https://huggingface.co/unsloth/Llama-3.1-8B-Instruct-GGUF/resolve/main/Llama-3.1-8B-Instruct-UD-Q4_K_M.gguf"
    models["openchat3.5"]="https://huggingface.co/TheBloke/openchat_3.5-GGUF/resolve/main/openchat_3.5.Q4_K_M.gguf"
    models["mistral-7b"]="https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf"
    models["mistral-7b-claude"]="https://huggingface.co/TheBloke/Mistral-7B-Claude-Chat-GGUF/resolve/main/mistral-7b-claude-chat.Q4_K_M.gguf"
    models["gpt4all-falcon"]="https://huggingface.co/tensorblock/gpt4all-falcon-GGUF/resolve/main/gpt4all-falcon-Q4_K_M.gguf"
    models["airoboros-llama2-gpt4.1-7b"]="https://huggingface.co/TheBloke/airoboros-l2-7b-gpt4-1.4.1-GGUF/resolve/main/airoboros-l2-7b-gpt4-1.4.1.Q4_K_M.gguf"
    models["airoboros-llama2-gpt4.2-7b"]="https://huggingface.co/TheBloke/airoboros-l2-7B-gpt4-2.0-GGUF/resolve/main/airoboros-l2-7B-gpt4-2.0.Q4_K_M.gguf"
    models["kimi-k2"]="https://huggingface.co/ubergarm/Kimi-K2-Instruct-GGUF/resolve/main/mainline/imatrix-mainline-pr9400-plus-kimi-k2-942c55cd5-Kimi-K2-Instruct-Q4_K_M.gguf"
    models["kimiko-claude"]="https://huggingface.co/mradermacher/Kimiko-Claude-FP16-GGUF/resolve/main/Kimiko-Claude-FP16.Q4_K_M.gguf"
fi

# --- Main Script ---

# Ensure the target directory exists
echo "Ensuring directory '$TARGET_DIR' exists..."
mkdir -p "$TARGET_DIR"

# Loop through the array and download each model
for name in "${!models[@]}"; do
    url="${models[$name]}"
    # Extract filename from the end of the URL
    filename=$(basename "$url")
    # Define the full output path
    output_path="$TARGET_DIR/$filename"
    
    echo "--- Checking model: $name ---"

    if [ -f "$output_path" ]; then
        echo "✅ Model already exists at $output_path. Skipping download."
    else
        echo "Downloading model: $name..."
        wget -q --show-progress --content-disposition -O "$output_path" "$url"
        echo "✅ Finished downloading to $output_path"
    fi
    echo ""
done

echo ""
echo "--- Checking for stale models in $TARGET_DIR ---"

# Create a list of expected filenames from the models array
expected_files=()
for url in "${models[@]}"; do
    expected_files+=("$(basename "$url")")
done

# Find all .gguf files in the target directory and check if they are expected
found_stale_model=false
for file_path in "$TARGET_DIR"/*.gguf; do
    if [ -f "$file_path" ]; then # Check if it's a file and not the glob pattern itself
        filename=$(basename "$file_path")
        if ! [[ " ${expected_files[*]} " =~ " ${filename} " ]]; then
            echo "[WARN] Found stale model file not in the current config: $filename. Deleting it."
            rm "$file_path"
            found_stale_model=true
        fi
    fi
done

[ "$found_stale_model" = false ] && echo "No stale models found."
echo "All downloads complete."