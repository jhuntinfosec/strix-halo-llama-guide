### 📜 Optimized `README.md` for Strix Halo

```markdown
# 🚀 Strix Halo (8060S) llama.cpp Optimization Guide

This repository provides the definitive setup for running large dense models (e.g., **Gemma 4 31B**) on **AMD Strix Halo (gfx1151)** hardware using **ROCm 7.2.2** on **Pop!_OS**.

## 💻 Hardware & OS Profile
- **APU**: AMD Ryzen AI Max+ (Strix Halo)
- **iGPU**: Radeon 8060S (gfx1151 / 40 Compute Units)
- **RAM**: 64GB LPDDR5x-8000 (Unified Architecture)
- **OS**: Pop!_OS 22.04 / 24.04 (Kernel 6.18.7+)
- **ROCm**: 7.2.2

---

## 🛠 1. Prerequisites & ROCm Setup
Before building, you must ensure the correct ROCm repositories are mapped and the system has the proper compiler headers.

### Add ROCm Repositories & Pinning
```bash
# Add ROCm signing key and repository
wget [https://repo.radeon.com/rocm/rocm.gpg.key](https://repo.radeon.com/rocm/rocm.gpg.key) -qO - | gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] [https://repo.radeon.com/rocm/apt/latest](https://repo.radeon.com/rocm/apt/latest) $(lsb_release -cs 2>/dev/null) main" | sudo tee --append /etc/apt/sources.list.d/rocm.list

# Set repo priority (Pinning)
echo -e 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600' | sudo tee /etc/apt/preferences.d/rocm-pin-600

sudo apt update
sudo apt install rocm build-essential cmake ccache libstdc++-13-dev g++-13
```

### Set User Permissions
```bash
sudo usermod -aG render,video $USER
# LOG OUT and LOG IN for this to take effect
```

---

## ⚙️ 2. OS Configuration (GTT Unlock)
On Strix Halo, the iGPU is restricted to 50% of system RAM by default. To load 31B+ models, you must unlock the Graphics Translation Table (GTT) limit.



### Increase GTT Size & Enable IOMMU Passthrough
Pop!_OS uses `kernelstub`. Run these to allow the iGPU to address up to 48GB:
```bash
sudo kernelstub -a "amdgpu.gttsize=49152"
sudo kernelstub -a "iommu=pt"
# REBOOT REQUIRED
```

---

## 🏗 3. Building llama.cpp
Targeting **gfx1100** ensures stability against "Illegal Instruction" errors while allowing us to spoof the native **gfx1151** ID at runtime.

⚠️ **Avoid Homebrew**: Do not use `brew install llama.cpp`. It lacks the specific HIP kernels needed for Strix Halo hardware acceleration.

```bash
git clone [https://github.com/ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
cd llama.cpp

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

## 🏃 4. The "Winning" Run Command
This configuration solves the **100% CPU stall** and **0% GPU usage** bugs.

```bash
# Advanced MMQ & Hardware Spoofing
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export ROCBLAS_TARGET=gfx1100
export GGML_CUDA_MMQ_X=48 
export GGML_CUDA_MMQ_Y=64 
export GGML_CUDA_NWARPS=4
export HSA_ENABLE_SDMA=0

./build/bin/llama-cli \
    -m models/gemma-4-31b-it-abliterated-t126-Q4_K_M.gguf \
    -ngl 99 \
    -fa on \
    -c 65536 \
    -ctk q8_0 -ctv q8_0 \
    -dio \
    --no-mmap \
    --threads 8 \
    -b 1024 -ub 1024 \
    -p "<|think|>\n"
```

### Why this works:
- **`-dio` & `--no-mmap`**: The "Silver Bullet." Fixes loading hangs on APUs by bypassing mmap page-fault loops.
- **`--threads 8`**: Prevents the CPU from saturating the memory bus, leaving bandwidth for the iGPU.
- **`MMQ` Variables**: Tunes Matrix Multiplication to the specific Compute Unit alignment of the 8060S.

---

## 🤖 5. Automated Workflows & Launcher Scripts

To avoid manual exports and typos, use these wrapper scripts. They ensure the environment is correctly spoofed for every session.

### 1. Interactive CLI Launcher (`run_gemma.sh`)
Use this for one-off research tasks and testing.
```bash
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export ROCBLAS_TARGET=gfx1100
export HIP_VISIBLE_DEVICES=0
export HSA_ENABLE_SDMA=0
# MMQ Tuning
export GGML_CUDA_MMQ_X=48
export GGML_CUDA_MMQ_Y=64
export GGML_CUDA_NWARPS=4

./build/bin/llama-cli -m [PATH_TO_MODEL] -ngl 99 -fa on -c 32768 -dio --no-mmap --threads 8 "$@"
```

### 2. Local API Node (`serve_gemma.sh`)
Use this to turn your Strix Halo into an OpenAI-compatible API endpoint (Port 8080).
```bash
#!/bin/bash
# (Includes same exports as above)
./build/bin/llama-server -m [PATH_TO_MODEL] --host 0.0.0.0 --port 8080 -ngl 99 -fa on -c 65536 -ctk q8_0 -ctv q8_0 -dio --no-mmap --threads 8 --jinja
```

---

## ⚙️ 6. Systemd Service (Autostart)

To make your **Gemma 4 Intelligence Node** persistent across reboots on Pop!_OS, set it up as a system service.


### 1. Create the Service File
```bash
sudo nano /etc/systemd/system/gemma-node.service
```

### 2. Paste the Configuration
*Replace `YOUR_USER` and `/path/to/llama.cpp` with your actual details.*

```ini
[Unit]
Description=Gemma 4 Intelligence Node (Strix Halo)
After=network.target

[Service]
# Group=render is essential for ROCm/GPU access
User=YOUR_USER
Group=render
WorkingDirectory=/home/YOUR_USER/llama.cpp
ExecStart=/bin/bash /home/YOUR_USER/llama.cpp/serve_gemma.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### 3. Enable and Start
```bash
sudo systemctl daemon-reload
sudo systemctl enable gemma-node
sudo systemctl start gemma-node

# Check status
sudo systemctl status gemma-node
```

Your system will  automatically initialize the iGPU and load the 31B model into memory the moment you boot into Pop!_OS. You can instantly query it from any script or app via `http://localhost:8080`.

---


## 📈 Performance Targets (31B Q4_K_M)
- **Prompt Processing**: ~50.7 t/s
- **Generation**: ~9.4 t/s
- **Monitoring**: `nvtop` often reports 0% due to a driver bug. Use the direct kernel path to verify:
  ```bash
  watch -n 0.5 cat /sys/class/drm/card0/device/gpu_busy_percent
  ```

---

## 🧠 Architecture: RDNA 3 vs 3.5
The Radeon 8060S (Strix Halo) uses RDNA 3.5. While more efficient, ROCm 7.2.2 libraries are often better optimized for the baseline RDNA 3 (`gfx1100`). Spoofing the hardware ID allows the model to utilize highly mature kernels while running on the latest 256-bit unified memory bus.

## Miscellaneous
If you're running Pop! OS on a laptop, make sure your power settings set to `High Performance`
