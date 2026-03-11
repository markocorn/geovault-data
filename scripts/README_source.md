# Running Benchmarks

## Hardware 

- **OS:** Ubuntu 24.04.3 LTS
- **Kernel:** 6.14.0-35-generic
- **CPU:** Intel® Xeon® Gold 6338 @ 2.00 GHz (16 cores, 1 thread/core)
- **OpenCL (CPU runtime):** PoCL 5.0 (OpenCL 3.0) — device: `cpu-skylake-avx512-Intel(R) Xeon(R) Gold 6338 CPU @ 2.00GHz`

> Note: With the current setup, Hashcat uses the **CPU OpenCL** device via PoCL unless a GPU OpenCL/CUDA backend is available.
---

## BIP-39 CPU Benchmarks

### Software 

- **Hashcat:** v6.2.6 (running in **CPU-only** mode via OpenCL)
- **OpenCL platform for Hashcat CPU backend:** Portable Computing Language (**PoCL**) 5.0

### Running the Benchmarks
```bash
./bip39_cpu.sh 
```

### Results
- **Python (hashlib):** ~**1.742 ms/check** (≈ **574 checks/s**)
- **Hashcat (CPU OpenCL via PoCL):** ~**0.01938 ms/check** (≈ **51,608 checks/s**)
- **Speedup (Hashcat vs Python):** **~89.9×**


## BIP-39 GPU Benchmarks

###  Software 

- **Hashcat:** v6.2.6
- **GPU:** NVIDIA RTX A6000 (48 GiB)
- **CUDA Runtime:** 12.0
- **NVIDIA Driver:** (from `nvidia-smi`)
- **OpenCL:** not required (Hashcat uses CUDA on NVIDIA)

```bash
./bip39_gpu.sh

## Argon2 CPU Benchmarks
```bash
./argon2_cpu.sh
```

### Results

**GPU:** NVIDIA RTX A6000 (≈49,140 MiB VRAM)

- **Hashcat mode:** 12100 (PBKDF2-HMAC-SHA512)
- **Raw speed @ 999 iters (R₉₉₉):** ~1,359,600 H/s
- **Scaled to 2048 iters (R₂₀₄₈):** ~663,203.320 H/s
- **Per-check time (T_GPU):** ~0.001508 ms

## What3Words Benchmarking Results (Single Cell, No KDF)

- **Entropy (H):** 45.7 bits
- **Search space (N):** 2^45.7 ≈ 57,157,180,927,446.49

### CPU (Defender) — SHA-256 via Hashcat (`-m 1400 -D 1`)
- **Throughput (R_CPU):** ≈ 927,900,000 H/s
- **Full brute-force time (W_CPU):**
    - ≈ 61,598.43 seconds
    - ≈ 17.1107 hours
    - ≈ 0.7129 days

### GPU (Attacker) — SHA-256 via Hashcat (`-m 1400`)
- **Throughput (R_GPU):** ≈ 9,595,000,000 H/s
- **Full brute-force time (W_GPU):**
    - ≈ 5,956.98 seconds
    - ≈ 1.6547 hours
    - ≈ 0.0689 days

## Argon2 CPU Benchmarks

### Software

- **argon2 (CLI):** Ubuntu package `argon2` (used for timing single Argon2id hashes)
- **libargon2:** system library used by the `argon2` CLI
- **bc:** 1.07.1 (for precise ms/us calculations)
- **coreutils (date):** for high-resolution timers
- **CPU OpenCL runtime (present but not used here):** PoCL 5.0 (OpenCL 3.0)

## Argon2 CPU Benchmarks — Results (Argon2id, t=1, p=1)

Runs per point: 60

| m_exp | Memory (MiB) | Avg time (ms) | Std dev (ms) | Checks/s |
|------:|-------------:|--------------:|-------------:|---------:|
| 20    | 1,024        | 2,567.878     | 78.898       | 0.389427 |
| 21    | 2,048        | 5,235.744     | 180.491      | 0.190995 |
| 22    | 4,096        | 10,681.459    | 318.634      | 0.093620 |
| 23    | 8,192        | 23,336.475    | 537.212      | 0.042851 |