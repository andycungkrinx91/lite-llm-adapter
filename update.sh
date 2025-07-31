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

SERVICE_NAME="lite-llm-adapter"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

if [ ! -f "$SERVICE_FILE" ]; then
    error "Service file '$SERVICE_FILE' not found. Please run the installer first."
fi

# Extract the app user and directory from the service file
APP_USER=$(grep -oP '(?<=^User=).*' "$SERVICE_FILE")
APP_DIR=$(grep -oP '(?<=^WorkingDirectory=).*' "$SERVICE_FILE")
VENV_DIR="$APP_DIR/venv"

if [ -z "$APP_USER" ] || [ -z "$APP_DIR" ]; then
    error "Could not determine application user or directory from $SERVICE_FILE. The service file may be corrupted."
fi

# Determine the environment to update to.
if [ -n "$1" ]; then
    ENVIRONMENT="$1"
else
    info "No environment specified. Please choose which environment to update to."
    PS3="Select an option: "
    select env_choice in "dev" "prod"; do
        if [[ -n "$env_choice" ]]; then
            ENVIRONMENT="$env_choice"
            break
        else
            echo "Invalid selection. Please choose 1 or 2."
        fi
    done < /dev/tty # Explicitly read from the terminal to fix interactivity issues with sudo
fi

if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
    error "Invalid environment specified: '$ENVIRONMENT'. Must be 'dev' or 'prod'."
fi

# --- Main Update Logic ---
info "Starting application update process..."
info "Application directory: $APP_DIR"
info "Application user: $APP_USER"
info "Target environment: $ENVIRONMENT"

read -p "This will discard any local changes, pull the latest code, and restart the service for the '$ENVIRONMENT' environment. Are you sure? (y/N) " -n 1 -r
echo # Move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Update cancelled by user."
    exit 0
fi

info "Auto-detecting default git branch..."
DEFAULT_BRANCH=$(sudo -u "$APP_USER" -- sh -c "cd '$APP_DIR' && git remote show origin | grep 'HEAD branch' | cut -d' ' -f5")
if [ -z "$DEFAULT_BRANCH" ]; then
    warn "Could not auto-detect default branch. Falling back to 'master' as a default."
    DEFAULT_BRANCH="master"
fi
info "Will reset to 'origin/$DEFAULT_BRANCH'"

info "Fetching the latest code from git..."
# Running git commands as the application user for correct permissions.
# We use 'git reset --hard' to ensure a clean update, discarding any local modifications.
sudo -u "$APP_USER" -- sh -c "cd '$APP_DIR' && git fetch origin && git reset --hard origin/$DEFAULT_BRANCH"

if systemctl is-active --quiet "$SERVICE_NAME"; then
    info "Stopping the '$SERVICE_NAME' service..."
    systemctl stop "$SERVICE_NAME"
else
    info "Service '$SERVICE_NAME' is not running, no need to stop it."
fi

info "Setting environment to '$ENVIRONMENT' in .env file..."
# Use sed to update the ENVIRONMENT variable in the .env file, running as the app user.
sudo -u "$APP_USER" -- sed -i "s/^ENVIRONMENT=.*/ENVIRONMENT=$ENVIRONMENT/" "$APP_DIR/.env"

info "Updating Python dependencies..."
sudo -u "$APP_USER" -- sh -c "cd '$APP_DIR' && CMAKE_ARGS='-DLLAMA_BLAS=ON -DLLAMA_BLAS_VENDOR=OpenBLAS' '$VENV_DIR/bin/pip' install --no-cache-dir -r requirements.txt"

info "Checking for new or updated models to download..."
info "This will download new models from the config without deleting existing ones."
sudo -u "$APP_USER" -- sh -c "cd '$APP_DIR' && ./models-downloader.sh '$ENVIRONMENT' --no-cleanup"

info "Restarting the '$SERVICE_NAME' service with the updated code..."
systemctl start "$SERVICE_NAME"

info "Waiting for the service to become available (up to 30 seconds)..."
for i in {1..15}; do
    # The service binds to 0.0.0.0:8000, so we can check it via localhost.
    if curl --fail --silent http://localhost:8000/health > /dev/null; then
        info "✅ Update complete! The '$SERVICE_NAME' service is running."
        info "You can check the status with: sudo systemctl status $SERVICE_NAME"
        exit 0
    fi
    sleep 2
done

# If the loop finishes without success, the service failed to start.
error "The service failed to start after the update. Please check the logs with: sudo journalctl -u $SERVICE_NAME -n 100"
