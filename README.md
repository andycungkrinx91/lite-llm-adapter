
## 🎯 Lite-LLM Adapter
> Serve multiple GGUF models via a production-ready, OpenAI-compatible API. Blazing-fast, stateful, and developer-friendly.

---

### ✨ **Features at a Glance**
| 🚀 Feature                        | 📌 Description |
|----------------------------------|----------------|
| **Multi-Model Serving**        | Dynamically load and serve multiple GGUF models from a simple JSON configuration. |
| **OpenAI-Compatible API**      | Drop-in replacement for OpenAI with `/v1/chat/completions` & `/v1/models` endpoints. |
| **Optimized CPU Inference**    | Built with `llama.cpp` and OpenBLAS for high-performance, multi-threaded CPU inference. |
| **Stateful, Streaming Chat**   | Supports persistent conversations using a `session_id` and `text/event-stream` for real-time responses. |
| **Concurrency Management**     | A Redis-based queue ensures smooth processing and prevents server overloads. |
| **Secure & Production-Ready**  | Protects endpoints with bearer token authentication. Deploy with Docker or as a native `systemd` service. |
| **Automated Testing**          | Includes a full end-to-end testing script using LXC for clean-room validation. |
| **Developer-Friendly**         | Features detailed system prompts, robust error handling, and clear documentation. |

---

### 📂 Project Structure
```
lite-llm-adapter/
├── .env.example            # Environment variable template
├── Dockerfile              # Defines the application's container image
├── docker-compose.yml      # Defines services for Docker deployment
├── installer.sh            # Installer for native systemd deployment
├── main.py                 # FastAPI application entrypoint
├── models-downloader.sh    # Script to download GGUF model files
├── requirements.txt        # Python dependencies
├── update.sh               # Script to update a systemd deployment
├── dependencies.py         # FastAPI dependency injection setup
├── models/
│   ├── model_config_dev.json     # Model definitions for 'dev' env
│   ├── model_config_prod.json    # Model definitions for 'prod' env
│   ├── model_config_defaults.json# Default parameters for all models
│   ├── model_loader.py       # Logic for loading models on-demand
│   └── gguf_models/          # (Downloaded .gguf files go here)
├── routers/
│   └── chat.py               # API routes for /v1/chat and /v1/models
├── schemas/
│   └── openai_types.py       # Pydantic schemas for OpenAI compatibility
└── services/
    ├── concurrency_manager.py# Redis-based queue for request concurrency
    └── local_llm.py          # Wrapper for llama-cpp-python interaction
```
---

## 🚀 **Quick Start**

### 🛠️ Prerequisites
- Git
- Docker + Docker Compose
- LXD (for local testing with `local-test.sh`)

---

### 🧬 **1. Clone the Repo**
```bash
git clone https://github.com/andycungkrinx91/lite-llm-adapter.git
cd lite-llm-adapter
```

---

### 🤖 **2. Download LLM Models**
```bash
# For dev (small models)
./models-downloader.sh

# For production models
./models-downloader.sh prod
```

---

### 🐳 **3. Deploy via Docker (Recommended)**
#### 🧪 Prepare `.env`
```bash
cp .env.example .env
AUTH_TOKEN=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)
sed -i "s/^AUTH=.*/AUTH=$AUTH_TOKEN/" .env
```

#### 🛸 Launch the App
```bash
docker-compose up --build
```
> 🔗 Access at: [http://localhost:8000](http://localhost:8000)

---

### 🧑‍💻 **4. Native Deployment (Systemd)**
```bash
sudo ./installer.sh
```

Then manage it like this:
```bash
sudo systemctl start lite-llm-adapter
sudo journalctl -u lite-llm-adapter -f
```

---

## 🧾 **Environment Configuration**

| Key                     | Purpose | Default |
|------------------------|---------|---------|
| `ENVIRONMENT`          | `dev` or `prod` for model config | `dev` |
| `DEFAULT_MODEL_ID`     | Default fallback model ID | `qwen3-0.6b` |
| `MODEL_BASE_PATH`      | Directory for GGUF files | `/app/models/gguf_models` |
| `REDIS_URL`            | Redis connection URI | `redis://localhost:6379` |
| `CPU_THREADS`          | Inference threads for `llama.cpp` | `4` |
| `OPENBLAS_NUM_THREADS` | **Crucial for CPU control.** Must match `CPU_THREADS`. | `4` |
| `AUTH`                 | Bearer token for auth | random |
| `MAX_CONCURRENT_REQUESTS` | Request concurrency limit | `1` |

---

## 🧠 **Model JSON Example**

```json
{
  "id": "qwen3-0.6b",
  "model_type": "local_gguf",
  "path": "Qwen3-0.6B-Q4_K_M.gguf",
  "system_prompt": "You are a helpful AI assistant.",
  "chat_format": "chatml",
  "params": {
    "n_ctx": 4096,
    "n_batch": 1024,
    "temperature": 0.7,
    "max_tokens": 2048
  }
}
```

---

## 💡 **Model Recommendations**

| Use Case                       | Recommended Models                                                              |
|--------------------------------|---------------------------------------------------------------------------------|
| **General Chat & Q&A**      | `qwen3-4b-nyx-v1`, `llama3.2-3b`, `phi4-mini`, `smolvlm2-2.2b-instruct`             |
| **Expert Coding**           | `blitzar-coder-4b`, `tiny-qwen3-coder-4b`, `qwen2.5-coder-3b`, `deepseek-coder-1.3b` |
| **Logical Reasoning**       | `qwen3-deepseek-reasoning`, `gemma-3-4b-ko-reasoning`, `phi4-mini-reasoning`      |
| **Document Writing**        | `gemma-3-4b-doc-writer`                                                         |
| **Specialized Tasks**       | `qwen2.5-vl-diagram2sql` (Diagrams to SQL), `smolvlm2-500m-video` (Video Analysis) |
| **Fast & Lightweight**       | `qwen3-0.6b`, `qwen2.5-coder-0.5b`, `llama3.2-1b`, `gemma-3-1b`                    |

> **Note**: Larger models (e.g., 4B) are generally more capable but slower and require more resources than smaller models (e.g., <3B).


## 🔌 API Usage Examples

First, set your auth token as an environment variable for convenience:
```bash
export API_TOKEN="your-secret-token-from-.env-file"
```

### 1. List Available Models

```bash
curl http://localhost:8000/v1/models \
  -H "Authorization: Bearer $API_TOKEN"
```

### 2. Start a New Chat (Non-Streaming)

This will return a complete JSON object with the response and a `session_id` for continuing the conversation.

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-0.6b",
    "messages": [{"role": "user", "content": "What is the capital of France?"}]
  }'
```

### 3. Continue a Chat Session (Streaming)

Use the `session_id` from the previous response and set `"stream": true`. The response will be a `text/event-stream`.

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-0.6b",
    "session_id": "paste-the-session-id-from-previous-response-here",
    "stream": true,
    "messages": [{"role": "user", "content": "And what is its population?"}]
  }'
```

### 4. Override Generation Parameters

You can override any default generation parameter, such as `temperature`.

```json
{
  "model": "qwen3-0.6b",
  "temperature": 0.2,
  "messages": [{"role": "user", "content": "Tell me a short, factual story."}]
}
```

---

## 🛠️ **Troubleshooting**

| ❗ Problem                           | 💡 Solution |
|------------------------------------|-------------|
| **High CPU Usage** (100%)          | Ensure `CPU_THREADS` and `OPENBLAS_NUM_THREADS` are set to a low number (e.g., 4) in your `.env` file. |
| **Slow Performance**               | Reduce `n_batch` / `n_ctx` in model configs, set `MAX_CONCURRENT_REQUESTS=1`. |
| **Redis Errors** / History Not Stored | Check `REDIS_URL` in `.env` is correct for your environment (Docker vs. native). |

> 🧪 Docker Logs: `docker-compose logs backend`  
> 🧾 Systemd Logs: `sudo journalctl -u lite-llm-adapter -f`

---

## 🧪 **Run Local Test (LXC)**
```bash
./local-test.sh
```
This will spin up a full containerized environment and simulate an end-to-end test (LXD required).

---

## 🛠️ **Tech Stack**
- � **GGUF** - Local model format
- ⚙️ **Gunicorn** - Production process manager


## ©️ Author
Made with ☕ by **Andy Setiyawan**, 2025.
