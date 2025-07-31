#!/bin/bash

#
# Local Test Cleanup Script
# This script stops and deletes the LXC container created by local-test.sh.
#

# Stop on any error
set -e

# --- Configuration ---
readonly CONTAINER_NAME="lite-llm-adapter-test"
readonly MINIMAL_IMAGE_ALIAS="minimal-ubuntu-24.04-lite-llm-adapter"

# --- Helper Functions ---
info() {
    echo "[INFO] $1"
}

# --- Main Cleanup Logic ---
info "--- Starting Test Environment Cleanup ---"

if lxc info "$CONTAINER_NAME" &>/dev/null; then
    info "Found container '$CONTAINER_NAME'."
    if lxc info "$CONTAINER_NAME" | grep -q "Status: RUNNING"; then
        info "Stopping container..."
        lxc stop "$CONTAINER_NAME"
    fi
    info "Deleting container..."
    lxc delete "$CONTAINER_NAME"
    info "✅ Cleanup complete."
else
    info "Container '$CONTAINER_NAME' not found. Nothing to do."
fi

# Optional: Clean up the image alias created by the test script
if [[ "$1" == "--all" || "$1" == "--image" ]]; then
    if lxc image info "$MINIMAL_IMAGE_ALIAS" &>/dev/null; then
        info "Deleting image alias '$MINIMAL_IMAGE_ALIAS'..."
        lxc image delete "$MINIMAL_IMAGE_ALIAS"
    fi
fi
