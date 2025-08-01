#!/bin/bash

#
# Local Test Script using LXC
# This script creates a clean, minimal LXC container, installs the application,
# and downloads development models for end-to-end testing.
# It builds a minimal image on first run to speed up subsequent tests.
#

# Stop on any error
set -e

# --- Configuration ---
readonly CONTAINER_NAME="lite-llm-adapter-test"
readonly MINIMAL_IMAGE_ALIAS="minimal-ubuntu-24.04-lite-llm-adapter"
readonly TEMP_BUILDER_NAME="lite-llm-adapter-builder"

readonly BASE_IMAGE="ubuntu:24.04" # Use the dedicated Ubuntu remote for better reliability

# Get the absolute path of the directory where this script is located. This is more reliable than 'pwd'.
readonly PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly APP_USER="llm_backend" # This must match the user in installer.sh --non-interactive
readonly APP_INSTALL_DIR="/home/app/site/lite-llm-adapter" # This must match the dir in installer.sh
readonly HOST_MODELS_DIR="${PROJECT_DIR}/models/gguf_models"
readonly CONTAINER_MODELS_PATH="${APP_INSTALL_DIR}/models/gguf_models"

# --- Helper Functions ---
info() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# --- Pre-flight Checks ---
if ! command -v lxc &> /dev/null; then
    error "lxc command not found. Please install LXD (e.g., 'sudo snap install lxd && sudo lxd init')."
fi

info "Checking for LXD remote 'ubuntu'..."
if ! lxc remote list | grep -q "ubuntu"; then
    error "LXD remote 'ubuntu' not found. This is required to download official Ubuntu images.
Please add it with the command:
lxc remote add ubuntu ubuntu.lxd.canonical.com"
fi

# --- Part 1: Create Minimal Image if it doesn't exist ---
if ! lxc image info "$MINIMAL_IMAGE_ALIAS" &>/dev/null; then
    info "Minimal image '$MINIMAL_IMAGE_ALIAS' not found. Creating it now..."

    # Clean up temp builder container if it exists from a failed previous run
    if lxc info "$TEMP_BUILDER_NAME" &>/dev/null; then
        lxc delete --force "$TEMP_BUILDER_NAME"
    fi

    info "Attempting to launch builder container from image: $BASE_IMAGE"
    if ! lxc launch "$BASE_IMAGE" "$TEMP_BUILDER_NAME"; then
        error "Failed to launch builder container with image '$BASE_IMAGE'.
Please check your LXD setup and network connection.
You can list available Ubuntu images with the command:
lxc image list ubuntu:"
    fi
    info "Successfully launched builder container '$TEMP_BUILDER_NAME'."

    info "Waiting for the temporary container to boot and get network..."
    # Wait for network to be up before proceeding
    for i in {1..30}; do
        if lxc exec "$TEMP_BUILDER_NAME" -- ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
            info "Network is up."
            break
        fi
        sleep 2
    done

    info "Shrinking the container by removing non-essential files..."
    lxc exec "$TEMP_BUILDER_NAME" -- bash -c '
        set -ex
        apt-get update
        apt-get -y autoremove --purge
        apt-get -y clean
        rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /usr/share/locale/*
        rm -rf /var/lib/apt/lists/* /var/cache/apt/*
        find /var/log -type f -exec truncate -s 0 {} \;
    '

    info "Cleaning cloud-init state to ensure it runs on new instances..."
    lxc exec "$TEMP_BUILDER_NAME" -- cloud-init clean --logs

    info "Stopping the temporary container..."
    lxc stop "$TEMP_BUILDER_NAME"

    info "Publishing the container as a new image: '$MINIMAL_IMAGE_ALIAS'..."
    lxc publish "$TEMP_BUILDER_NAME" --alias "$MINIMAL_IMAGE_ALIAS"

    info "Cleaning up the temporary container..."
    lxc delete "$TEMP_BUILDER_NAME"

    info "Success! Minimal image '$MINIMAL_IMAGE_ALIAS' has been created."
else
    info "Minimal image '$MINIMAL_IMAGE_ALIAS' already exists. Skipping creation."
fi

# --- Part 2: Run the test environment using the minimal image ---
info "--- Starting Test Environment Setup ---"

info "Downloading development models to the host..."
if ! bash "${PROJECT_DIR}/models-downloader.sh"; then
    error "Failed to download development models. Aborting."
fi

# Clean up any previous container with the same name for a fresh start.
if lxc info "$CONTAINER_NAME" &>/dev/null; then
    info "Found existing '$CONTAINER_NAME' container. Deleting it for a clean run."
    lxc delete --force "$CONTAINER_NAME"
fi

info "Launching new container '$CONTAINER_NAME' from image '$MINIMAL_IMAGE_ALIAS'..."
lxc launch "$MINIMAL_IMAGE_ALIAS" "$CONTAINER_NAME"

info "Applying resource limits to the container..."
lxc config set "$CONTAINER_NAME" limits.cpu 8
lxc config set "$CONTAINER_NAME" limits.memory 8GB
info "Set container limits: 8 CPU cores, 8GB RAM."

info "Waiting for container to boot and initialize..."
lxc exec "$CONTAINER_NAME" -- cloud-init status --wait

# --- 3. Deploy and Setup Application ---
info "Configuring container devices..."
lxc config device add "$CONTAINER_NAME" api-proxy proxy listen=tcp:0.0.0.0:8000 connect=tcp:127.0.0.1:8000
lxc config device add "$CONTAINER_NAME" project-source disk source="$PROJECT_DIR" path=/app

info "Ensuring installer scripts are executable..."
# Make the main installer executable.
chmod +x "$PROJECT_DIR/installer.sh"
# Also make all the modular install scripts executable (if any were added).
chmod +x "$PROJECT_DIR"/??-*/install.sh 2>/dev/null || true

info "Running the installer.sh script inside the container..."
info "Using --non-interactive flag for automated setup."
lxc exec "$CONTAINER_NAME" -- /bin/bash /app/installer.sh --non-interactive

info "Mounting models directory into the container..."
lxc config device add "$CONTAINER_NAME" models-mount disk source="$HOST_MODELS_DIR" path="$CONTAINER_MODELS_PATH"

info "Starting the service to apply changes and test..."
lxc exec "$CONTAINER_NAME" -- sudo systemctl start lite-llm-adapter

info "Waiting for the service to become available (up to 30 seconds)..."
for i in {1..15}; do
    if curl --fail --silent http://localhost:8000/health > /dev/null; then
        info "✅ Service is up and running."
        break
    fi
    sleep 2
done

if ! curl --fail --silent http://localhost:8000/health > /dev/null; then
    error "Service failed to start. Check logs with: lxc exec $CONTAINER_NAME -- sudo journalctl -u lite-llm-adapter -n 50"
fi

info "--- Test Environment Setup Complete ---"
info "The service is now running inside the LXC container."
echo
echo "API Endpoint is forwarded to: http://localhost:8000"
echo "To access the container shell, run: lxc exec $CONTAINER_NAME -- /bin/bash"
echo "To stop and delete the container, run: ./local-test-cleanup.sh"
echo "To also delete the minimal image, run: ./local-test-cleanup.sh --image"
