# 🚀 Strix Halo (8060S) llama.cpp Optimization Guide

This repository provides a comprehensive guide and optimized configuration for running large language models (like **Gemma 4 31B**) on the **AMD Strix Halo (gfx1151)** architecture. 

Specifically tailored for **Pop!_OS** users with **64GB of RAM**, this documentation solves common issues like the "100% CPU stall," "0% GPU usage," and "Illegal Instruction" errors.

## 💻 Hardware & OS Profile
- **Platform**: AMD Ryzen AI Max+ (Strix Halo)
- **iGPU**: Radeon 8060S (gfx1151 / 40 Compute Units)
- **RAM**: 64GB LPDDR5x-8000 (Unified Architecture)
- **OS**: Pop!_OS 22.04 / 24.04
- **Kernel**: 6.18.7-76061807-generic (or newer)
- **ROCm Version**: 7.2.2

---

## 🛠 1. System Configuration (GTT Unlock)
By default, the Linux `amdgpu` driver limits the iGPU to 50% of system RAM. To run a 31B model with 64K+ context, you must unlock this limit to allow the iGPU to address a larger portion of the 64GB pool.

### Update Kernel Parameters
Pop!_OS uses `kernelstub`. Run the following to set the GTT size to 48GB and enable IOMMU passthrough for better compute performance:

```bash
sudo kernelstub -a "amdgpu.gttsize=49152"
sudo kernelstub -a "iommu=pt"
sudo usermod -aG render,video $USER
# REBOOT REQUIRED after running these commands
```

---

## 🏗 2. Building llama.cpp
The ROCm 7.2.2 compiler for `gfx1151` can generate "Illegal Instruction" errors (wavefront shift issues). We solve this by targeting the mature `gfx1100` (RDNA 3) instruction set and spoofing the ID at runtime.

### Dependencies
Ensure you have the GCC 13 toolchain installed, as Clang 22 often struggles with GCC 14 headers on newer Pop!_OS builds:
```bash
sudo apt install libstdc++-13-dev g++-13
```

### Build Command
```bash
cmake -S . -B build \
    -DGGML_HIP=ON \
    -DGPU_TARGETS=gfx1100 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH=/opt/rocm-7.2.2 \
    -DCMAKE_HIP_FLAGS="--gcc-install-dir=/usr/lib/gcc/x86_64-linux-gnu/13" \
    -DCMAKE_HIP_COMPILER="$(hipconfig -l)/clang"

cmake --build build --config Release -- -j $(nproc)
```

---

## 🏃 3. The "Winning" Execution Command
This specific combination of environment variables and flags bypasses the memory-mapped file conflicts and bus contention issues inherent to the Strix Halo architecture.

```bash
# Force the ROCm runtime to use gfx1100 kernels on gfx1151 hardware
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export HSA_ENABLE_SDMA=0
export ROCBLAS_TARGET=gfx1100

./build/bin/llama-cli \
    -m models/gemma-4-31b-it-abliterated-t126-Q4_K_M.gguf \
    -ngl 99 \
    -fa on \
    -c 65536 \
    -ctk q8_0 -ctv q8_0 \
    -dio \
    --no-mmap \
    --threads 8 \
    -p "<|think|>\n"
```

### Key Flag Explanations:
- **`-dio` & `--no-mmap`**: **The Silver Bullet.** Bypasses the memory-mapped file conflict that causes infinite page-fault loops and 100% CPU stalls during model loading on shared-memory APUs.
- **`-fa on`**: Enables Flash Attention, utilizing the RDNA 3.5 `ROCWMMA` instructions for a 2x-3x speedup in long-context processing.
- **`--threads 8`**: Capping threads prevents the CPU from saturating the memory bus, leaving maximum bandwidth for the iGPU.
- **`-ctk q8_0`**: Quantizes the KV cache to 8-bit, allowing 64K context to fit comfortably within the 48GB GTT window.

---

## 📈 Performance & Monitoring
### Expected Stats (Gemma 4 31B)
- **Prompt Processing**: ~50+ t/s
- **Generation**: ~9.4 t/s

### The "0% GPU" Monitoring Bug
On the Radeon 8060S, `nvtop` and `amd-smi` often report 0% GPU utilization even when the hardware is under full load. This is a reporting bug. To see real-time hardware activity, use the direct kernel interface:

```bash
watch -n 0.5 cat /sys/class/drm/card0/device/gpu_busy_percent
```

---

## 🧠 Why This Configuration?
1. **RDNA 3 vs 3.5**: While `gfx1151` is newer, ROCm 7.2.2 libraries often lack specific binary targets for it. Spoofing `gfx1100` allows us to use mature, highly-optimized kernels.
2. **Unified Memory Bus**: Unlike a dedicated GPU, the 8060S shares its LPDDR5x-8000 bus with the CPU. High CPU thread counts (e.g., `-t 16`) actually slow down the GPU by creating bus contention.
3. **Direct I/O**: APUs can hang when trying to `mmap` files larger than 16GB due to IOMMU and page-table limits. `-dio` ensures a clean stream into memory.

---

### Acknowledgments
Optimized through trial and error on Pop!_OS 22.04 / 24.04 with a 64GB Strix Halo engineering sample. 


```
