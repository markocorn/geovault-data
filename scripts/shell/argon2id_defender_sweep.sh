#!/usr/bin/env bash
# argon2id_defender_sweep.sh
#
# 2-D CPU latency sweep over Argon2id memory cost (m) and KDF chaining
# depth (k), modelling the full defender key-derivation cost.
#
# For each (mem_mib, k) pair the script runs REPS independent chain
# evaluations.  Each chain feeds the hex output of call i as plaintext
# for call i+1:
#
#   K_0 = INITIAL_SECRET
#   K_i = Argon2id( K_{i-1}, salt, t, m, p )   i = 1..k
#
# Output files (written to OUT_DIR):
#   defender_sweep_raw.csv      -- every (mem_mib, k, rep, call_idx) measurement
#   defender_sweep_summary.csv  -- per (mem_mib, k): mean_ms, std_ms, p50_ms, p95_ms
#
# Usage:
#   bash argon2id_defender_sweep.sh
#
# Override defaults via environment variables, e.g.:
#   MEM_LIST="64 256 1024" K_LIST="1 3 10" REPS=20 bash argon2id_defender_sweep.sh

set -euo pipefail

# ---- Config ---------------------------------------------------------------
# Memory tiers in MiB — matches paper Table 6 baseline rows
MEM_LIST="${MEM_LIST:-64 256 1024 8192}"
# Chaining depths — powers of 2 (each step doubles work)
K_LIST="${K_LIST:-1 2 4 8 16 32 64}"

T_COST="${T_COST:-1}"
P_LANES="${P_LANES:-1}"
HASHLEN="${HASHLEN:-32}"
REPS="${REPS:-30}"
SALT="${SALT:-geovault-salt}"
INITIAL_SECRET="${INITIAL_SECRET:-31415926535897}"
TYPE="id"
VERSION="13"

OUT_DIR="${OUT_DIR:-.}"
RAW_CSV="${OUT_DIR}/defender_sweep_raw.csv"
SUMMARY_CSV="${OUT_DIR}/defender_sweep_summary.csv"

read -r -a MEM_VALUES <<< "$MEM_LIST"
read -r -a K_VALUES   <<< "$K_LIST"

# ---- Dependency checks ----------------------------------------------------
for cmd in argon2 awk bc date sort; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: Missing dependency: $cmd"; exit 1; }
done

# ---- Temp files -----------------------------------------------------------
TIMING_FILE=$(mktemp)
HASH_FILE=$(mktemp)
# Accumulator file for per-(m,k) rep totals — used for percentile calc
REP_FILE=$(mktemp)
trap 'rm -f "$TIMING_FILE" "$HASH_FILE" "$REP_FILE"' EXIT

# ---- CSV headers ----------------------------------------------------------
echo "mem_mib,k,rep,call_idx,call_time_ms" > "$RAW_CSV"
echo "mem_mib,k,reps,mean_ms,std_ms,p50_ms,p95_ms" > "$SUMMARY_CSV"

# ---- Banner ---------------------------------------------------------------
echo "=== Argon2id Defender 2-D Sweep ==="
echo "Memory tiers (MiB) : ${MEM_VALUES[*]}"
echo "Chaining depths    : ${K_VALUES[*]}"
echo "t_cost             : $T_COST"
echo "p_lanes            : $P_LANES"
echo "Repetitions/cell   : $REPS"
echo "Output dir         : $OUT_DIR"
total_cells=$(( ${#MEM_VALUES[@]} * ${#K_VALUES[@]} ))
echo "Total (m,k) cells  : $total_cells  (each x$REPS reps)"
echo

# ---- Helper: run one Argon2id call ----------------------------------------
# $1 = plaintext  $2 = mem_kib
# Writes elapsed ms → TIMING_FILE, raw hex hash → HASH_FILE
run_one_argon2() {
  local plaintext="$1"
  local mem_kib="$2"
  local start_ns end_ns diff_ns

  start_ns=$(date +%s%N)

  printf "%s" "$plaintext" | \
    argon2 "$SALT" \
      -"$TYPE" \
      -v "$VERSION" \
      -t "$T_COST" \
      -k "$mem_kib" \
      -p "$P_LANES" \
      -l "$HASHLEN" \
      -r > "$HASH_FILE"

  end_ns=$(date +%s%N)
  diff_ns=$(( end_ns - start_ns ))
  echo "scale=6; $diff_ns / 1000000" | bc -l > "$TIMING_FILE"
}

# ---- Helper: percentile from sorted list ----------------------------------
# $1 = percentile (0-100)  $2 = sorted temp file (one value per line)
percentile() {
  local pct="$1"
  local file="$2"
  local n total_lines idx
  total_lines=$(wc -l < "$file")
  idx=$(echo "scale=0; (($pct * $total_lines + 99) / 100)" | bc)
  (( idx < 1 )) && idx=1
  (( idx > total_lines )) && idx=$total_lines
  sed -n "${idx}p" "$file"
}

# ---- Main 2-D sweep -------------------------------------------------------
cell=0
for mem_mib in "${MEM_VALUES[@]}"; do
  mem_kib=$(( mem_mib * 1024 ))

  for k in "${K_VALUES[@]}"; do
    cell=$(( cell + 1 ))
    echo "--- Cell $cell/$total_cells : m=${mem_mib} MiB, k=${k} ---"

    > "$REP_FILE"   # clear rep totals

    for rep in $(seq 1 "$REPS"); do
      current_input="$INITIAL_SECRET"
      total_ms="0"

      for call_idx in $(seq 1 "$k"); do
        run_one_argon2 "$current_input" "$mem_kib"
        call_ms=$(cat "$TIMING_FILE")
        current_input=$(cat "$HASH_FILE")

        echo "${mem_mib},${k},${rep},${call_idx},${call_ms}" >> "$RAW_CSV"
        total_ms=$(echo "scale=6; $total_ms + $call_ms" | bc -l)
      done

      echo "$total_ms" >> "$REP_FILE"
      printf "  rep %2d/%d : %.1f ms\n" "$rep" "$REPS" "$total_ms"
    done

    # ---- Statistics for this (m, k) cell ----------------------------------
    n="$REPS"
    sum=$(awk '{s+=$1} END{printf "%.6f",s}' "$REP_FILE")
    sum2=$(awk '{s+=$1*$1} END{printf "%.6f",s}' "$REP_FILE")

    mean=$(echo "scale=6; $sum / $n" | bc -l)
    var=$(echo "scale=10; v = $sum2/$n - ($mean*$mean); if(v<0) v=0; v" | bc -l)
    std=$(echo "scale=6; sqrt($var)" | bc -l)

    # Percentiles from sorted rep totals
    sort -n "$REP_FILE" > "${REP_FILE}.sorted"
    p50=$(percentile 50 "${REP_FILE}.sorted")
    p95=$(percentile 95 "${REP_FILE}.sorted")
    rm -f "${REP_FILE}.sorted"

    printf "  => mean=%.1f ms  std=%.1f ms  p50=%.1f ms  p95=%.1f ms\n\n" \
      "$mean" "$std" "$p50" "$p95"

    echo "${mem_mib},${k},${n},${mean},${std},${p50},${p95}" >> "$SUMMARY_CSV"
  done
done

# ---- Console summary table ------------------------------------------------
echo "=== Summary ==="
awk -F, '
NR==1 { next }
{
  printf "m=%-6s MiB  k=%-3s  mean=%8.1f ms  std=%7.1f ms  p50=%8.1f ms  p95=%8.1f ms\n",
    $1, $2, $4, $5, $6, $7
}
' "$SUMMARY_CSV"

echo
echo "Raw data  : $RAW_CSV"
echo "Summary   : $SUMMARY_CSV"
