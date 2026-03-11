#!/bin/bash
# bip39_gpu_pbkdf2_hashcat_raw.sh
# Collect RAW Hashcat GPU benchmark data for PBKDF2-HMAC-SHA512 (mode 12100).
# NO calculations are performed here (you will do scaling/stats in MATLAB).
#
# Output:
#   1) CSV with one row per run, containing the raw Speed.# line + parsed numeric + unit
#   2) Plain-text log file with progress + full hashcat output on parse failures
#
# CSV columns:
#   Timestamp,Run,DeviceFilter,Workload,SpeedLine,SpeedNum,SpeedUnit
#
# Notes:
# - Hashcat -b reports performance for its internal benchmark parameters (often 999 iterations for mode 12100).
# - This script does NOT scale to 2048; do that later in MATLAB.

set -euo pipefail

# ---- Config ----
RUNS="${RUNS:-1000}"
WARMUP="${WARMUP:-3}"
OUT_CSV="${OUT_CSV:-bip39_gpu_hashcat_raw.csv}"
OUT_LOG="${OUT_LOG:-bip39_gpu_hashcat_raw.log}"

# Optional: choose device(s) (hashcat backend device index), e.g. DEVICE=1
DEVICE="${DEVICE:-}"

# Optional: set workload profile, e.g. WORKLOAD=3 (default), 4=max
WORKLOAD="${WORKLOAD:-3}"

# ---- Dependency checks ----
for cmd in hashcat awk; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    echo "Install it, e.g.: sudo apt install hashcat gawk"
    exit 1
  fi
done

# ---- Header / environment logging ----
{
  echo "=== RAW Hashcat GPU Benchmark Logger (mode 12100) ==="
  echo "Started: $(date -Is)"
  echo "Hashcat: $(hashcat --version | head -n1 || true)"
  echo "RUNS=$RUNS  WARMUP=$WARMUP  WORKLOAD=$WORKLOAD  DEVICE=${DEVICE:-<all>}"
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo "GPU(s):"
    nvidia-smi --query-gpu=index,name,driver_version,pstate,power.limit,clocks.sm,clocks.mem,temperature.gpu --format=csv,noheader || true
  else
    echo "nvidia-smi: not found (skipping GPU metadata)"
  fi
  echo
} | tee "$OUT_LOG"

# ---- CSV header ----
echo "Timestamp,Run,DeviceFilter,Workload,SpeedLine,SpeedNum,SpeedUnit" > "$OUT_CSV"

# ---- Build hashcat command ----
HC_CMD=(hashcat -b -m 12100 -w "$WORKLOAD")
if [ -n "$DEVICE" ]; then
  HC_CMD+=(--backend-devices "$DEVICE")
fi

# ---- Helper: parse Speed line robustly ----
# Returns 3 fields:
#   SpeedLine|SpeedNum|SpeedUnit
parse_speed_line() {
  local output="$1"
  local line num unit

  line="$(echo "$output" | grep -m1 "Speed.#" || true)"
  if [ -z "$line" ]; then
    return 1
  fi

  # Parse the first numeric + unit after the colon.
  # Example:
  # Speed.#1.........:  1379.3 kH/s (54.04ms) @ ...
  num="$(echo "$line" | awk -F: '{print $2}' | awk '{print $1}')"
  unit="$(echo "$line" | awk -F: '{print $2}' | awk '{print $2}')"

  echo "$line|$num|$unit"
}

# ---- Warmup ----
if [ "$WARMUP" -gt 0 ]; then
  echo "--- Warmup ($WARMUP runs, not recorded) ---" | tee -a "$OUT_LOG"
  for w in $(seq 1 "$WARMUP"); do
    "${HC_CMD[@]}" >/dev/null 2>&1 || true
    echo "Warmup $w/$WARMUP done" | tee -a "$OUT_LOG"
  done
  echo | tee -a "$OUT_LOG"
fi

# ---- Main benchmark runs ----
echo "--- Collecting $RUNS runs (recorded) ---" | tee -a "$OUT_LOG"

for i in $(seq 1 "$RUNS"); do
  ts="$(date -Is)"
  echo "Run $i/$RUNS @ $ts ..." | tee -a "$OUT_LOG"

  HC_OUTPUT="$("${HC_CMD[@]}" 2>&1 || true)"

  PARSED="$(parse_speed_line "$HC_OUTPUT" || true)"
  if [ -z "$PARSED" ]; then
    echo "ERROR: Could not parse Speed.# line on run $i" | tee -a "$OUT_LOG"
    echo "---- Hashcat output (run $i) ----" | tee -a "$OUT_LOG"
    echo "$HC_OUTPUT" | tee -a "$OUT_LOG"
    echo "---------------------------------" | tee -a "$OUT_LOG"
    exit 1
  fi

  SPEED_LINE="$(echo "$PARSED" | cut -d'|' -f1)"
  SPEED_NUM="$(echo "$PARSED"  | cut -d'|' -f2)"
  SPEED_UNIT="$(echo "$PARSED" | cut -d'|' -f3)"

  # Escape quotes for CSV safety
  SPEED_LINE_ESCAPED="$(echo "$SPEED_LINE" | sed 's/"/""/g')"

  # Write CSV row (SpeedLine quoted)
  printf '%s,%s,%s,%s,"%s",%s,%s\n' \
    "$ts" "$i" "${DEVICE:-}" "$WORKLOAD" "$SPEED_LINE_ESCAPED" "$SPEED_NUM" "$SPEED_UNIT" \
    >> "$OUT_CSV"

  echo "  Parsed: $SPEED_NUM $SPEED_UNIT" | tee -a "$OUT_LOG"
done

echo | tee -a "$OUT_LOG"
echo "Done." | tee -a "$OUT_LOG"
echo "CSV: $OUT_CSV" | tee -a "$OUT_LOG"
echo "LOG: $OUT_LOG" | tee -a "$OUT_LOG"
