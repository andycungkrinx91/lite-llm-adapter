# Lite-LLM Adapter

This project provides a high-performance, scalable, and production-ready adapter service designed to serve multiple local GGUF language models through an OpenAI-compatible API. It's built with FastAPI and `llama-cpp-python` for speed and efficiency, using Redis for robust concurrency management and stateful conversation handling.

## ✨ Key Features

- **OpenAI-Compatible API**: Drop-in replacement for applications using the OpenAI API. Supports `/v1/chat/completions` and `/v1/models`.
- **Multi-Model Support**: Dynamically load and serve any number of GGUF models based on simple JSON configurations.
- **Environment-Specific Configurations**: Use `model_config_dev.json` for lightweight development and `model_config_prod.json` for a full suite of production models.
- **Optimized for CPU Performance**: Natively supports `llama.cpp` features like model quantization (e.g., `Q4_K_M`) and BLAS acceleration to deliver fast inference on standard CPU hardware.
- **Asynchronous & Scalable**: Built on FastAPI and Uvicorn for non-blocking request handling. Uses a Redis-based queue to manage concurrent requests, ensuring smooth processing under high load and enabling horizontal scaling.
- **Intelligent System Prompts**: Define default system prompts in your model configurations. The API intelligently injects them, while still allowing users to override them with their own prompts.
- **Scalable Concurrency Management**: Uses a Redis-based queue to manage concurrent requests, ensuring smooth processing even under high load and enabling horizontal scaling.
- **Stateful Conversations**: Offloads chat history to Redis, allowing for persistent, multi-turn conversations via a `session_id`.
- **Streaming & Non-Streaming**: Natively supports both streaming (`text/event-stream`) and standard JSON responses.
- **Secure API**: Protects endpoints with token-based authentication.
- **Robust Deployment & Updates**: Includes a `docker-compose.yml` for quick containerized setup and an interactive `installer.sh` for production `systemd` deployments. A dedicated `update.sh` script handles safe, non-destructive updates.
- **Automated Local Testing**: A powerful `local-test.sh` script creates a clean, isolated LXC container to run a full, automated end-to-end installation and test.
- **Enhanced Error Handling**: Provides clear, actionable error messages for common issues like missing model files or misconfigurations.

---

## 🚀 Getting Started

You can deploy the service using either Docker (recommended for a quick start) or a `systemd` service on a dedicated Linux server.

### Prerequisites

- Git
- Docker & Docker Compose (for Docker deployment)
- LXD (for running the automated local test script)

### 1. Clone the Repository

```bash
git clone https://github.com/andycungkrinx91/lite-llm-adapter.git
cd lite-llm-adapter
```

### 2. Download Models

The `models-downloader.sh` script can fetch models for either a `dev` or `prod` environment.

```bash
# For development (downloads two small models)
./models-downloader.sh

# For production (downloads all configured models)
./models-downloader.sh prod
```

### 3. Choose Your Deployment Method

#### Option A: Docker Deployment (Recommended)

1.  **Create Environment File**: Copy the example and generate a secret key.
    > **Note**: The `docker-compose.yml` file is configured to automatically connect to the Redis container using its service name (`redis`), so you don't need to change `REDIS_URL` in the `.env` file for Docker.
    ```bash
    cp .env.example .env
    # Generate a secure, random API key and update the .env file.
    AUTH_TOKEN=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)
    sed -i "s/^AUTH=.*/AUTH=$AUTH_TOKEN/" .env
    echo "A new secret AUTH token has been generated in your .env file."
    ```

2.  **Launch Services**: Use Docker Compose to build and run the backend and Redis containers.
    ```bash
    docker-compose up --build
    ```

The API will be available at `http://localhost:8000`.

#### Option B: Systemd Deployment (Production on Linux)

The `installer.sh` script automates the setup of a production-ready service on a Debian-based system (like Ubuntu 24.04).

1.  **Run the Installer**:
    ```bash
    sudo ./installer.sh # Run in interactive mode
    ```
    This script will:
    - Interactively prompt you for configuration values (user, directory, default model).
    - Create a dedicated system user (defaults to `app`).
    - Set up the application in a structured directory (e.g., `/home/app/site/lite-llm-adapter`).
    - Create a production `.env` file with a secure, random `AUTH` token.
    - Configure and enable a `systemd` service.

2.  **Start and Manage the Service**:
    ```bash
    # Start the service
    sudo systemctl start lite-llm-adapter

    # Check its status
    sudo systemctl status lite-llm-adapter

    # View live logs
    sudo journalctl -u lite-llm-adapter -f
    ```

### 4. Updating the Service (Systemd Deployments)

To update your `systemd` deployment to the latest version from the git repository, a simple `update.sh` script is provided. It will safely pull the latest code, update dependencies, and download any new models without deleting your existing ones.

```bash
# Run the update script with root privileges
sudo ./update.sh
```

The script will interactively ask you which environment (`dev` or `prod`) you want to update to.

---

## ⚙️ Configuration

### Environment Variables (`.env`)

The application is configured using a `.env` file.

| Variable                  | Description                                                              | Default          |
| ------------------------- | ------------------------------------------------------------------------ | ---------------- |
| `ENVIRONMENT`             | Set to `dev` or `prod` to load the corresponding model config.           | `dev` (in `.env.example`) |
| `DEFAULT_MODEL_ID`        | The model to use if one isn't specified in the API request.              | `qwen3-0.6b`     |
| `MODEL_BASE_PATH`         | The absolute path to the directory containing GGUF model files.          | `/app/models/gguf_models` |
| `REDIS_URL`               | The connection string for the Redis instance.                            | `redis://localhost:6379` |
| `CPU_THREADS`             | Number of CPU threads to use for model inference.                        | `4`              |
| `AUTH`                    | The secret bearer token for API authentication.                          | (randomly generated) |
| `MAX_CONCURRENT_REQUESTS` | The number of simultaneous requests the service can process. **Set to `1` for memory-constrained systems.** | `1` (in `.env.example`) |

### Model Configuration (`models/model_config_*.json`)

Models are defined in `models/model_config_dev.json` and `models/model_config_prod.json`. Each model entry has the following structure:

```json
{
  "id": "qwen3-0.6b", // Unique identifier for the model
  "model_type": "local_gguf",
  "path": "Qwen3-0.6B-Q4_K_M.gguf", // Filename within MODEL_BASE_PATH
  "system_prompt": "You are a helpful AI assistant.", // Optional default system prompt
  "chat_format": "chatml", // The chat template to use (e.g., chatml, llama-3)
  "params": {
    "n_ctx": 4096, // Llama.cpp constructor parameter: context size
    "n_batch": 1024, // Llama.cpp constructor parameter: batch size
    "temperature": 0.7, // Default generation parameter
    "max_tokens": 2048 // Default generation parameter
  }
}
```

---

## 🔌 API Usage

All requests must include the `Authorization` header with the bearer token from your `.env` file.

### List Available Models

```bash
curl http://localhost:8000/v1/models \
  -H "Authorization: Bearer your-secret-token"
```

### Create a Chat Completion (Non-Streaming)

This request starts a new conversation. The server generates a unique `session_id` and returns it in the response, allowing you to continue the chat later.

**Request:**
```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-secret-token" \
  -d '{
    "model": "qwen3-0.6b",
    "messages": [
      {"role": "user", "content": "Hello! What is FastAPI?"}
      // You can also provide a system prompt here, which will override
      // the default one from the model's configuration for this request.
      // {"role": "system", "content": "You are a teacher."},
      // {"role": "user", "content": "Hello! What is FastAPI?"}
    ]
  }'
```

### Continue a Conversation

Provide the `session_id` from the previous response to continue the conversation. The backend will automatically retrieve the chat history from Redis.

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-secret-token" \
  -d '{
    "model": "qwen3-0.6b",
    "session_id": "the-session-id-from-previous-response",
    "messages": [
      {"role": "user", "content": "How does it compare to Flask?"}
    ]
  }'
```

### Create a Chat Completion (Streaming)

Set `"stream": true` to receive a `text/event-stream` response. The first chunk will contain the `session_id`.

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-secret-token" \
  -d '{
    "model": "qwen3-0.6b",
    "messages": [
      {"role": "user", "content": "Write a short poem about code."}
    ],
    "stream": true
  }'
```

---

## 🔬 Development & Testing

For a fully automated, clean-room test of the entire installation process, use the `local-test.sh` script. This script spins up a fresh LXC container (think of it as a super-fast, lightweight virtual machine—cheers to all the infra folks who make this magic possible!) to ensure the installation is perfect from scratch.

**Prerequisites**: LXD must be installed (`sudo snap install lxd && sudo lxd init`).

```bash
./local-test.sh
```

This script will:
1.  Create a minimal Ubuntu 24.04 image on the first run to speed up subsequent tests.
2.  Launch a clean LXC container.
3.  Mount the project directory into the container.
4.  Run `installer.sh` to set up the entire application and `systemd` service.
5.  Run `models-downloader.sh dev` to fetch development models.
6.  Start the service and run a health check.

The API will be forwarded to `http://localhost:8000` on your host machine.

---

## 🛠️ Technology Stack

- **Backend Framework**: FastAPI
- **LLM Inference**: llama-cpp-python
- **Data Caching & Queuing**: Redis
- **Process Manager**: Gunicorn & Uvicorn
- **Containerization**: Docker & Docker Compose
- **Test Environment**: LXD

---

## 📜 Authored

Copyright (c) 2025 Andy Setiyawan
