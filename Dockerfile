# --- CPU Build Stage ---
# This stage builds llama-cpp-python without any GPU acceleration.
FROM python:3.12-slim AS cpu-builder

WORKDIR /app

# Set environment variables to build with OpenBLAS for CPU acceleration,
# while explicitly disabling all GPU backends. This is crucial for performance.
ENV CMAKE_ARGS="-DLLAMA_BLAS=ON -DLLAMA_BLAS_VENDOR=OpenBLAS -DLLAMA_CUBLAS=OFF -DLLAMA_HIPBLAS=OFF -DLLAMA_CLBLAST=OFF"
ENV FORCE_CMAKE=1

# Install system dependencies required for building wheels
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    libopenblas-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy and install dependencies. This is done in a separate layer to leverage Docker's cache.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- Final Application Stage ---
# This is the final image that will be run.
# It starts from a slim Python image for a smaller size. It must match the builder version.
FROM python:3.12-slim

WORKDIR /app

# Install runtime dependencies for the compiled llama.cpp library.
# - libgomp1 is the GNU OpenMP library, for multi-threaded CPU inference.
# - libopenblas0 is the runtime library for OpenBLAS, for accelerated matrix math.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libopenblas0 \
    && rm -rf /var/lib/apt/lists/*

# Copy the pre-built, CPU-only wheels from the `cpu-builder` stage.
COPY --from=cpu-builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=cpu-builder /usr/local/bin /usr/local/bin

# Copy the rest of the application code
COPY . .

# --- Diagnostic Step ---
# List the contents of the /app directory recursively to verify that all
# source files, including the 'schemas' directory, have been copied correctly.
# This runs during the build process and will appear in the build logs.
RUN echo "--- Verifying file structure in /app ---" && ls -R

# Expose the port the app runs on
EXPOSE 8000

# The command to run the application using Uvicorn
# This is often overridden by docker-compose.yml for production deployments.
CMD ["gunicorn", "-k", "uvicorn.workers.UvicornWorker", "-w", "1", "--timeout", "120", "--pythonpath", "/app", "main:app", "--bind", "0.0.0.0:8000"]