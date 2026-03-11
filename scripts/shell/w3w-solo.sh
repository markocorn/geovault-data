#!/bin/bash
# w3w_sha256_workfactor.sh
# Compute defender and attacker work factors for a single What3Words cell
# without KDF, using hashcat SHA-256 (mode 1400) throughput.
#
# - Defender: CPU-only hashcat (OpenCL CPU backend)
# - Attacker: GPU hashcat (default CUDA / GPU backend)
# - Entropy: H = 45.7 bits (single W3W cell)
#
# Work factor model:
#   N       = 2^H                (search space size)
#   W_att   = N / R              (seconds of brute force)
#
# Requires: hashcat, bc (with math library), and a CPU OpenCL runtime (e.g. PoCL).

set -euo pipefail

# ---- Config ----
H_BITS=45.7                     # entropy of one W3W cell (in bits)
HASH_MODE=1400                  # SHA-256 in hashcat

# ---- Dependency checks ----
for cmd in hashcat bc; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    echo "Install it (e.g. sudo apt install hashcat bc)"
    exit 1
  fi
done

echo "=== What3Words (single cell, no KDF) – SHA-256 work factor via hashcat ==="
echo "Entropy H = ${H_BITS} bits"
echo

########################################
# 1) Compute search space size N=2^H   #
########################################

N=$(echo "scale=10; e($H_BITS*l(2))" | bc -l)

echo "Search space size:"
echo "  N = 2^${H_BITS} ≈ ${N}"
echo

########################################
# Helper: parse hashcat Speed.# line   #
########################################
parse_speed_line () {
  local line="$1"

  # Example lines:
  #   Speed.#1.........:  1234.5 kH/s ...
  #   Speed.#2.........:  98765 H/s ...
  local num unit
  num=$(echo "$line"  | awk '{print $2}')   # e.g. 1234.5
  unit=$(echo "$line" | awk '{print $3}')   # e.g. kH/s

  local mult
  case "$unit" in
    H/s)  mult=1 ;;
    kH/s) mult=1000 ;;
    MH/s) mult=1000000 ;;
    GH/s) mult=1000000000 ;;
    *)
      echo "Unexpected unit: $unit (full line: $line)" >&2
      mult=1
      ;;
  esac

  # Return R = num * mult as float
  echo "$num * $mult" | bc -l
}

########################################
# 2) Defender: CPU-only hashcat        #
########################################

echo "--- Defender: CPU-only SHA-256 benchmark (hashcat -b -m ${HASH_MODE} -D 1) ---"
HC_CPU=$(hashcat -b -m "${HASH_MODE}" -D 1 2>&1 || true)

if echo "$HC_CPU" | grep -qi "No devices found\|No devices suitable"; then
  echo "No CPU OpenCL device available for hashcat (defender throughput not computed)."
  HAVE_CPU=0
else
  SPEED_LINE_CPU=$(echo "$HC_CPU" | grep -m1 "Speed.#" || true)
  if [ -z "$SPEED_LINE_CPU" ]; then
    echo "Could not parse CPU speed line. Raw output:" >&2
    echo "$HC_CPU"
    HAVE_CPU=0
  else
    R_CPU=$(parse_speed_line "$SPEED_LINE_CPU")
    HAVE_CPU=1

    # Work factor: W = N / R
    W_CPU_SEC=$(echo "scale=10; $N / $R_CPU" | bc -l)
    W_CPU_H=$(echo "scale=6; $W_CPU_SEC / 3600" | bc -l)
    W_CPU_D=$(echo "scale=6; $W_CPU_H / 24" | bc -l)

    echo "CPU defender throughput (SHA-256):"
    echo "  R_CPU ≈ ${R_CPU} hashes/s"
    echo "  W_CPU (full brute force):"
    echo "    ≈ ${W_CPU_SEC} seconds"
    echo "    ≈ ${W_CPU_H} hours"
    echo "    ≈ ${W_CPU_D} days"
    echo
  fi
fi

########################################
# 3) Attacker: GPU hashcat             #
########################################

echo "--- Attacker: GPU SHA-256 benchmark (hashcat -b -m ${HASH_MODE}) ---"
HC_GPU=$(hashcat -b -m "${HASH_MODE}" 2>&1 || true)

SPEED_LINE_GPU=$(echo "$HC_GPU" | grep -m1 "Speed.#" || true)
if [ -z "$SPEED_LINE_GPU" ]; then
  echo "Could not parse GPU speed line. Raw output:" >&2
  echo "$HC_GPU"
  HAVE_GPU=0
else
  R_GPU=$(parse_speed_line "$SPEED_LINE_GPU")
  HAVE_GPU=1

  W_GPU_SEC=$(echo "scale=10; $N / $R_GPU" | bc -l)
  W_GPU_H=$(echo "scale=6; $W_GPU_SEC / 3600" | bc -l)
  W_GPU_D=$(echo "scale=6; $W_GPU_H / 24" | bc -l)

  echo "GPU attacker throughput (SHA-256):"
  echo "  R_GPU ≈ ${R_GPU} hashes/s"
  echo "  W_GPU (full brute force):"
  echo "    ≈ ${W_GPU_SEC} seconds"
  echo "    ≈ ${W_GPU_H} hours"
  echo "    ≈ ${W_GPU_D} days"
  echo
fi

########################################
# 4) Summary                           #
########################################

echo "=== Summary: What3Words (1 cell, no KDF) ==="
echo "Entropy: H = ${H_BITS} bits, N = 2^H ≈ ${N}"

if [ "${HAVE_CPU:-0}" -eq 1 ]; then
  echo "Defender-like CPU speed (hashcat -D 1):   R_CPU ≈ ${R_CPU} H/s"
  echo "  Full brute force time (CPU):            ≈ ${W_CPU_H} hours (≈ ${W_CPU_D} days)"
fi

if [ "${HAVE_GPU:-0}" -eq 1 ]; then
  echo "Attacker GPU speed (hashcat default):     R_GPU ≈ ${R_GPU} H/s"
  echo "  Full brute force time (GPU):            ≈ ${W_GPU_H} hours (≈ ${W_GPU_D} days)"
fi

