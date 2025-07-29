#!/bin/bash

# Installer for the Lite-LLM Adapter Service
# This script sets up the application to run under systemd on a Debian-based system (like Ubuntu).

# Stop on any error
set -e

# --- Configuration ---
APP_USER="llm_backend"
APP_GROUP="llm_backend"
APP_DIR="/home/app/site/lite-llm-adapter"
MODEL_DIR="$APP_DIR/models/gguf_models"
VENV_DIR="$APP_DIR/venv"
LOG_DIR="$APP_DIR/logs"
SERVICE_NAME="lite-llm-adapter"

# --- Helper Functions ---
info() {
    echo "[INFO] $1"
}

warn() {
    echo "[WARN] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# Get the absolute path of the directory where this script is located. This is more reliable than 'pwd'.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# --- Pre-flight Checks ---
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root. Please use 'sudo ./installer.sh'."
fi

info "Starting Lite-LLM Adapter installation..."

# --- 1. System Dependencies ---
info "Updating package lists and installing dependencies (python3.12, venv, pip, redis, rsync)..."
apt-get update
apt-get install -y python3.12 python3.12-venv python3-pip redis-server rsync

info "Enabling and starting Redis service..."
systemctl enable --now redis-server.service

# --- 2. Create Application User and Directories ---
info "Creating application user and group '$APP_USER'..."
if ! getent group "$APP_GROUP" >/dev/null; then
    addgroup --system "$APP_GROUP"
else
    info "Group '$APP_GROUP' already exists."
fi

if ! id "$APP_USER" >/dev/null 2>&1; then
    adduser --system --ingroup "$APP_GROUP" --no-create-home --shell /usr/sbin/nologin "$APP_USER"
else
    info "User '$APP_USER' already exists."
fi

info "Creating application directories..."
mkdir -p "$APP_DIR"
mkdir -p "$MODEL_DIR"
mkdir -p "$LOG_DIR"

# --- 3. Application Setup ---
info "Copying application files to $APP_DIR..."
rsync -a --exclude='models/gguf_models/*' --exclude='.git/' "$SCRIPT_DIR/" "$APP_DIR/"

info "Creating Python virtual environment at $VENV_DIR..."
python3.12 -m venv "$VENV_DIR"

info "Installing Python dependencies into the virtual environment..."
"$VENV_DIR/bin/pip" install --no-cache-dir -r "$APP_DIR/requirements.txt"

# --- 4. Configuration (.env file) ---
info "Creating production .env file..."
cat > "$APP_DIR/.env" << EOF
# --- Production Environment Configuration ---
ENVIRONMENT=prod
DEFAULT_MODEL_ID=qwen3-0.6b
MODEL_BASE_PATH=$MODEL_DIR
REDIS_URL=redis://localhost:6379
CPU_THREADS=$(nproc)
AUTH=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 ; echo '')
MAX_CONCURRENT_REQUESTS=3
EOF

info "A new secret AUTH token has been generated in $APP_DIR/.env"
warn "Please NOTE DOWN this AUTH token. You will need it to access the API."
warn "AUTH Token: $(grep AUTH "$APP_DIR/.env" | cut -d '=' -f2)"

# --- 5. Set Permissions ---
info "Setting ownership and permissions..."
chown -R "$APP_USER":"$APP_GROUP" "$APP_DIR"
chown -R "$APP_USER":"$APP_GROUP" "$LOG_DIR"
chown -R "$APP_USER":"$APP_GROUP" "$MODEL_DIR"
chmod -R 750 "$APP_DIR"
chmod -R 750 "$LOG_DIR"
chmod -R 750 "$MODEL_DIR"

# --- 6. Create systemd Service File ---
info "Creating systemd service file for '$SERVICE_NAME'..."
cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=Lite-LLM Adapter Service
After=network.target redis-server.service
Requires=redis-server.service

[Service]
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$APP_DIR
EnvironmentFile=$APP_DIR/.env
ExecStart=$VENV_DIR/bin/gunicorn -k uvicorn.workers.UvicornWorker -w 1 --timeout 600 --bind 0.0.0.0:8000 --pythonpath $APP_DIR main:app
StandardOutput=append:$LOG_DIR/app.log
StandardError=append:$LOG_DIR/error.log
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# --- 7. Final Steps ---
info "Reloading systemd daemon and enabling the service..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME.service"

info "Installation complete!"
warn "----------------------------------------------------------------"
warn "IMPORTANT: You must now download your GGUF models and place them"
warn "in the '$MODEL_DIR' directory."
warn "The application will not find any models until you do this."
warn "----------------------------------------------------------------"
info "To start the service now, run: sudo systemctl start $SERVICE_NAME"
info "To check the service status, run: sudo systemctl status $SERVICE_NAME"
info "To view logs, run: sudo tail -f $LOG_DIR/app.log"
