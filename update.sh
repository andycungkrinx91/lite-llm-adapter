#!/bin/bash

# Update script for the Lite-LLM Adapter
# This script automates the process of updating the application to the latest version from git.
# It relies on the installer.sh script to re-apply configurations.

# Stop on any error
set -e

# --- Helper Functions ---
info() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# --- Pre-flight Checks ---
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root. Please use 'sudo ./update.sh'."
fi

# Get the absolute path of the directory where this script is located.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SERVICE_NAME="lite-llm-adapter"

# --- Main Update Logic ---
info "Starting application update process..."

info "Navigating to project directory: $SCRIPT_DIR"
cd "$SCRIPT_DIR"

info "Fetching the latest code from git..."
if ! git pull; then
    error "Failed to pull latest code from git. Please check your git configuration and network connection."
fi

info "Stopping the '$SERVICE_NAME' service..."
if systemctl is-active --quiet "$SERVICE_NAME"; then
    systemctl stop "$SERVICE_NAME"
    info "Service stopped."
else
    info "Service was not running, which is fine."
fi

info "Re-running the installer to apply updates..."
# The installer will detect the existing configuration and run non-interactively.
if ! bash ./installer.sh; then
    error "The installer script failed. Please check the output for errors."
fi

info "Restarting the '$SERVICE_NAME' service with the updated code..."
systemctl restart "$SERVICE_NAME"

info "Waiting a few seconds for the service to initialize..."
sleep 5

# Check the status to confirm it's running.
if systemctl is-active --quiet "$SERVICE_NAME"; then
    info "✅ Update complete! The '$SERVICE_NAME' service is running."
    info "You can check the status with: sudo systemctl status $SERVICE_NAME"
else
    error "The service failed to start after the update. Please check the logs with: sudo journalctl -u $SERVICE_NAME -n 100"
fi
