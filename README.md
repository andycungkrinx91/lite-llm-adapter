# Lite-LLM Adapter

This project provides a high-performance, scalable, and modular adapter service designed to serve multiple local GGUF language models through an OpenAI-compatible API. It's built with FastAPI and `llama-cpp-python` for speed and efficiency, using Redis for robust concurrency management and stateful conversation handling.

## ✨ Key Features

- **OpenAI-Compatible API**: Drop-in replacement for applications using the OpenAI API. Supports `/v1/chat/completions` and `/v1/models`.
- **Multi-Model Support**: Dynamically load and serve any number of GGUF models based on simple JSON configurations.
- **Environment-Specific Configurations**: Use `model_config_dev.json` for lightweight development and `model_config_prod.json` for a full suite of production models.
- **High-Performance & Asynchronous**: Built on FastAPI and Uvicorn for non-blocking, asynchronous request handling.
- **Scalable Concurrency Management**: Uses a Redis-based queue to manage concurrent requests, ensuring smooth processing even under high load and enabling horizontal scaling.
- **Stateful Conversations**: Offloads chat history to Redis, allowing for persistent, multi-turn conversations via a `session_id`.
- **Streaming & Non-Streaming**: Natively supports both streaming (`text/event-stream`) and standard JSON responses.
- **Secure API**: Protects endpoints with token-based authentication.
- **Easy Deployment**: Includes a `docker-compose.yml` for quick containerized setup and a comprehensive `installer.sh` for production `systemd` deployments on Linux.
- **Automated Local Testing**: A powerful `local-test.sh` script creates a clean, isolated LXC container to run a full end-to-end installation and test.

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
    # The .env file will be pre-filled, but you can customize it.
    # A unique AUTH token is generated automatically.
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
    sudo ./installer.sh
    ```
    This script will:
    - Install dependencies (`python3.12`, `redis-server`, etc.).
    - Create a dedicated system user (`llm_backend`).
    - Set up the application in `/home/app/site/multi-llm-adapter`.
    - Create a production `.env` file with a secure, random `AUTH` token.
    - Configure and enable a `systemd` service.

2.  **Start the Service**:
    ```bash
    sudo systemctl start multi-llm-backend
    ```

3.  **Check Status and Logs**:
    ```bash
    # Check status
    sudo systemctl status multi-llm-backend

    # View logs
    sudo journalctl -u multi-llm-backend -f
    ```

---

## ⚙️ Configuration

### Environment Variables (`.env`)

The application is configured using a `.env` file.

| Variable                  | Description                                                              | Default          |
| ------------------------- | ------------------------------------------------------------------------ | ---------------- |
| `ENVIRONMENT`             | Set to `dev` or `prod` to load the corresponding model config.           | `dev`            |
| `DEFAULT_MODEL_ID`        | The model to use if one isn't specified in the API request.              | `qwen3-0.6b`     |
| `MODEL_BASE_PATH`         | The absolute path to the directory containing GGUF model files.          | `/app/models/gguf_models` |
| `REDIS_URL`               | The connection string for the Redis instance.                            | `redis://localhost:6379` |
| `CPU_THREADS`             | Number of CPU threads to use for model inference.                        | `4`              |
| `AUTH`                    | The secret bearer token for API authentication.                          | (randomly generated) |
| `MAX_CONCURRENT_REQUESTS` | The number of simultaneous requests the service can process. Others queue in Redis. | `3`              |

### Model Configuration (`models/model_config_*.json`)

Models are defined in `models/model_config_dev.json` and `models/model_config_prod.json`. Each model entry has the following structure:

```json
{
  "id": "qwen3-0.6b", // Unique identifier for the model
  "model_type": "local_gguf", // Type of model
  "path": "Qwen3-0.6B-BF16.gguf", // Filename within MODEL_BASE_PATH
  "chat_format": "qwen", // The chat template to use (e.g., chatml, llama-3)
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
