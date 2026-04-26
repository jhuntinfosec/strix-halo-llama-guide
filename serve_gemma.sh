#!/bin/bash

# --- Hardware Spoofing & ROCm Stabilizers ---
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export ROCBLAS_TARGET=gfx1100
export HIP_VISIBLE_DEVICES=0
export HSA_ENABLE_SDMA=0

# --- Strix Halo Performance Tuning (MMQ) ---
export GGML_CUDA_MMQ_X=48
export GGML_CUDA_MMQ_Y=64
export GGML_CUDA_NWARPS=4

# --- Configuration ---
MODEL_PATH="$HOME/llama.cpp/models/gemma-4-31b-it-abliterated-GGUF_gemma-4-31b-it-abliterated-t126-Q4_K_M.gguf"
HOST="0.0.0.0"
PORT="8080"
CTX="65536"

echo -e "\033[1;32m[+]\033[0m Initializing Strix Halo Local Intelligence Node..."
echo -e "\033[1;34m[*]\033[0m Target: Radeon 8060S (Spoofed to gfx1100)"
echo -e "\033[1;34m[*]\033[0m Endpoint: http://$HOST:$PORT/v1"

# --- Execute Server ---
./build/bin/llama-server \
    -m "$MODEL_PATH" \
    --host "$HOST" \
    --port "$PORT" \
    -ngl 99 \
    -fa on \
    -c "$CTX" \
    -ctk q8_0 -ctv q8_0 \
    -dio \
    --no-mmap \
    --threads 8 \
    --metrics \
    --jinja \
    "$@"
