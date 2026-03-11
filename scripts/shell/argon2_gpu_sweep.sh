#!/usr/bin/env bash
# argon2_gpu_sweep.sh
# GPU Argon2id runtime sweep over memory cost 2^m KiB (compatible with your CPU sweep CSVs).
#
# Usage:
#   ./argon2_gpu_sweep.sh [m_exp_start] [m_exp_end] [runs]
#
# Env overrides:
#   TIME_COST (default 1), PARALLELISM (default 1), TYPE (id), VERSION (1.3)
#   MODE (cuda|opencl, default cuda), DEVICE (default 0)
#   BUILD_DIR (defaults to $HOME/argon2-gpu/build)
#
# Output:
#   Summary CSV: argon2_gpu_m<mstart>_<mend>_r<runs>_summary.csv
#   Raw CSV:     argon2_gpu_m<mstart>_<mend>_r<runs>_raw.csv
#
# Columns (match CPU script):
#   Summary: m_exp,mem_kib,mem_mib,time_cost,parallelism,type,runs,avg_ms,std_ms
#   Raw:     m_exp,mem_kib,mem_mib,run_idx,ms

set -euo pipefail

###############
# Parameters  #
###############

TIME_COST="${TIME_COST:-1}"      # Argon2 t
PARALLELISM="${PARALLELISM:-1}"  # Argon2 p
TYPE="${TYPE:-id}"               # Argon2id
VERSION="${VERSION:-1.3}"        # Argon2 v=19

MEXP_START="${1:-10}"
MEXP_END="${2:-23}"
RUNS="${3:-20}"

PASSWORD="${PASSWORD:-example-w3w-password}"
SALT="${SALT:-example-w3w-salt}"   # (plain text; for hex use --salt-hex and set SALT to hex)

MODE="${MODE:-cuda}"               # cuda | opencl
DEVICE="${DEVICE:-0}"              # GPU index

SUMMARY_OUT="argon2_gpu_m${MEXP_START}_${MEXP_END}_r${RUNS}_summary.csv"
RAW_OUT="argon2_gpu_m${MEXP_START}_${MEXP_END}_r${RUNS}_raw.csv"

########################
# Build dir / binaries #
########################

BUILD_DIR="${BUILD_DIR:-$HOME/argon2-gpu/build}"
EXEC="$BUILD_DIR/argon2-exec"

# Ensure local libs (.so) are found when running from the build dir
export LD_LIBRARY_PATH="$BUILD_DIR:${LD_LIBRARY_PATH:-}"

#####################
# Dependency checks #
#####################

for cmd in bc date; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing: $cmd (install: sudo apt install bc coreutils)"; exit 1; }
done
[[ -x "$EXEC" ]] || { echo "Missing executable: $EXEC (build it with: make argon2-exec -j)"; exit 1; }

if (( MEXP_END < MEXP_START )); then
  echo "Error: m_exp_end ($MEXP_END) < m_exp_start ($MEXP_START)"
  exit 1
fi

echo "=== Argon2id GPU sweep ==="
echo "Mode/Device : $MODE / $DEVICE"
echo "Version     : $VERSION"
echo "Params      : t=$TIME_COST, p=$PARALLELISM, type=$TYPE, runs=$RUNS"
echo "m range     : $MEXP_START .. $MEXP_END (2^m KiB)"
echo "Build dir   : $BUILD_DIR"
echo "Summary CSV : $SUMMARY_OUT"
echo "Raw CSV     : $RAW_OUT"
echo

################
# CSV headers  #
################

[ -f "$SUMMARY_OUT" ] || echo "m_exp,mem_kib,mem_mib,time_cost,parallelism,type,runs,avg_ms,std_ms" > "$SUMMARY_OUT"
[ -f "$RAW_OUT" ]     || echo "m_exp,mem_kib,mem_mib,run_idx,ms" > "$RAW_OUT"

##############
# Main loop  #
##############

for MEXP in $(seq "$MEXP_START" "$MEXP_END"); do
  MEM_KIB=$((1 << MEXP))
  MEM_MIB=$((MEM_KIB / 1024))

  echo ">>> m_exp=${MEXP} (≈ ${MEM_MIB} MiB, ${MEM_KIB} KiB)"

  TOTAL_MS=0
  TOTAL_MS2=0

  for ((i=1; i<=RUNS; i++)); do
    START_NS=$(date +%s%N)

    # Compute a real Argon2 hash on GPU; discard output (we're measuring wall time)
    "$EXEC" \
      --mode="$MODE" \
      --device="$DEVICE" \
      --type="$TYPE" \
      --version="$VERSION" \
      --m-cost="$MEM_KIB" \
      --t-cost="$TIME_COST" \
      --lanes="$PARALLELISM" \
      --hash-len=32 \
      --salt "$SALT" \
      --password "$PASSWORD" \
      --output=encoded \
      > /dev/null

    END_NS=$(date +%s%N)
    D_NS=$((END_NS - START_NS))

    # ns -> ms (float)
    MS=$(echo "scale=6; $D_NS / 1000000" | bc -l)

    TOTAL_MS=$(echo "$TOTAL_MS + $MS" | bc -l)
    MS2=$(echo "$MS * $MS" | bc -l)
    TOTAL_MS2=$(echo "$TOTAL_MS2 + $MS2" | bc -l)

    printf "   run %d/%d: %.6f ms\n" "$i" "$RUNS" "$MS"
    printf "%d,%d,%d,%d,%.6f\n" "$MEXP" "$MEM_KIB" "$MEM_MIB" "$i" "$MS" >> "$RAW_OUT"
  done

  MEAN_MS=$(echo "scale=6; $TOTAL_MS / $RUNS" | bc -l)
  MEAN_MS2=$(echo "scale=6; $TOTAL_MS2 / $RUNS" | bc -l)
  VAR_MS=$(echo "scale=10; v=$MEAN_MS2-($MEAN_MS*$MEAN_MS); if(v<0) v=0; v" | bc -l)
  STD_MS=$(echo "scale=6; sqrt($VAR_MS)" | bc -l)

  printf "   -> average: %.6f ms, stddev: %.6f ms (mem ≈ %d MiB)\n\n" "$MEAN_MS" "$STD_MS" "$MEM_MIB"

  printf "%d,%d,%d,%d,%d,%s,%d,%.6f,%.6f\n" \
    "$MEXP" "$MEM_KIB" "$MEM_MIB" "$TIME_COST" "$PARALLELISM" "$TYPE" "$RUNS" "$MEAN_MS" "$STD_MS" >> "$SUMMARY_OUT"
done

echo "Sweep complete."
echo "Summary written to: $SUMMARY_OUT"
echo "Raw data written to: $RAW_OUT"
