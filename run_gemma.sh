#!/bin/bash

# Hardware Spoofing (Only for this process)
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export ROCBLAS_TARGET=gfx1100
export HIP_VISIBLE_DEVICES=0
export HSA_ENABLE_SDMA=0

# Performance Tuning
export GGML_CUDA_MMQ_X=48
export GGML_CUDA_MMQ_Y=64
export GGML_CUDA_NWARPS=4

# Execute llama-cli with your optimized arguments
./build/bin/llama-cli \
    -m models/gemma-4-31b-it-abliterated-GGUF_gemma-4-31b-it-abliterated-t126-Q4_K_M.gguf \
    -ngl 99 \
    -fa on \
    -c 32768 \
    -ctk q8_0 -ctv q8_0 \
    -dio \
    --no-mmap \
    --threads 8 \
    -p "<|think|>\n" "$@"
