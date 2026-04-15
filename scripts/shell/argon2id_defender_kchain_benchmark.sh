#!/usr/bin/env bash
# argon2id_defender_kchain_benchmark.sh
#
# Benchmarks KDF chaining depth k for Argon2id at a fixed memory cost.
# Each chain feeds the hex-encoded hash output of call i as the plaintext
# input of call i+1, matching the GeoVault protocol definition:
#
#   K_0 = initial_secret
#   K_i = Argon2id( K_{i-1}, salt, t, m, p )   i = 1..k
#
# For each (k, repetition) pair the script records:
#   - total wall-clock time for the full k-call chain
#   - each individual call time within the chain
#
# Output files (written to OUT_DIR):
#   kchain_raw.csv        -- per-call breakdown for every (k, rep, call_idx)
#   kchain_summary.csv    -- per (k, rep) totals + predicted linear value
#
# Usage:
#   bash argon2id_defender_kchain_benchmark.sh
#
# Override defaults via environment variables:
#   MEM_MIB=1024 REPS=5 K_LIST="1 2 4 8 16 32 64" bash argon2id_defender_kchain_benchmark.sh

set -euo pipefail

# ---- Config ----
MEM_MIB="${MEM_MIB:-1024}"
T_COST="${T_COST:-1}"
P_LANES="${P_LANES:-1}"
HASHLEN="${HASHLEN:-32}"
REPS="${REPS:-5}"
SALT="${SALT:-geovault-salt}"
INITIAL_SECRET="${INITIAL_SECRET:-31415926535897}"
TYPE="id"
VERSION="13"

# Space-separated list of chaining depths to benchmark
K_LIST="${K_LIST:-1 2 4 8 16 32 64}"
read -r -a K_VALUES <<< "$K_LIST"

OUT_DIR="${OUT_DIR:-.}"
RAW_CSV="${OUT_DIR}/kchain_raw.csv"
SUMMARY_CSV="${OUT_DIR}/kchain_summary.csv"

MEM_KIB=$(( MEM_MIB * 1024 ))

# Temp file used to pass timing out of subshells (bash subshells cannot
# write to parent-scope variables).
TIMING_FILE=$(mktemp)
HASH_FILE=$(mktemp)
trap 'rm -f "$TIMING_FILE" "$HASH_FILE"' EXIT

# ---- Dependency checks ----
for cmd in argon2 awk bc date; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: Missing dependency: $cmd"; exit 1; }
done

echo "=== Argon2id KDF Chaining Benchmark ==="
echo "Memory (MiB)     : $MEM_MIB"
echo "t_cost           : $T_COST"
echo "p_lanes          : $P_LANES"
echo "hash length      : $HASHLEN bytes"
echo "repetitions      : $REPS"
echo "k values         : ${K_VALUES[*]}"
echo "output dir       : $OUT_DIR"
echo

# ---- CSV headers ----
echo "k,rep,call_idx,call_time_ms" > "$RAW_CSV"
echo "k,rep,total_measured_ms,total_predicted_ms,ratio" > "$SUMMARY_CSV"

# ---- Helper: run one Argon2id call ----
# Args : $1 = plaintext string, $2 = mem_kib
# Writes elapsed ms to $TIMING_FILE
# Writes raw hex hash to $HASH_FILE
run_one_argon2() {
  local plaintext="$1"
  local mem_kib="$2"
  local start_ns end_ns diff_ns diff_ms hash_hex

  start_ns=$(date +%s%N)

  hash_hex=$(printf "%s" "$plaintext" | \
    argon2 "$SALT" \
      -"$TYPE" \
      -v "$VERSION" \
      -t "$T_COST" \
      -k "$mem_kib" \
      -p "$P_LANES" \
      -l "$HASHLEN" \
      -r)    # -r = raw hex, no decoration

  end_ns=$(date +%s%N)
  diff_ns=$(( end_ns - start_ns ))
  diff_ms=$(echo "scale=6; $diff_ns / 1000000" | bc -l)

  printf "%s" "$diff_ms"  > "$TIMING_FILE"
  printf "%s" "$hash_hex" > "$HASH_FILE"
}

# ---- Establish single-call baseline (k=1 repeated REPS times) ----
echo "--- Establishing k=1 baseline ---"
baseline_sum="0"
for rep in $(seq 1 "$REPS"); do
  run_one_argon2 "$INITIAL_SECRET" "$MEM_KIB"
  call_ms=$(cat "$TIMING_FILE")
  baseline_sum=$(echo "scale=6; $baseline_sum + $call_ms" | bc -l)
done
T1=$(echo "scale=6; $baseline_sum / $REPS" | bc -l)
printf "  T^(1) mean over %d reps : %.3f ms\n\n" "$REPS" "$T1"

# ---- Main sweep over k values ----
for k in "${K_VALUES[@]}"; do
  echo "--- k = $k ---"

  for rep in $(seq 1 "$REPS"); do
    current_input="$INITIAL_SECRET"
    total_ms="0"

    for call_idx in $(seq 1 "$k"); do
      run_one_argon2 "$current_input" "$MEM_KIB"
      call_ms=$(cat "$TIMING_FILE")
      current_input=$(cat "$HASH_FILE")   # chain: output becomes next input

      echo "${k},${rep},${call_idx},${call_ms}" >> "$RAW_CSV"
      total_ms=$(echo "scale=6; $total_ms + $call_ms" | bc -l)
    done

    predicted_ms=$(echo "scale=6; $k * $T1" | bc -l)
    ratio=$(echo "scale=6; $total_ms / $predicted_ms" | bc -l)

    printf "  rep %d: measured=%.1f ms  predicted=%.1f ms  ratio=%.4f\n" \
      "$rep" "$total_ms" "$predicted_ms" "$ratio"
    echo "${k},${rep},${total_ms},${predicted_ms},${ratio}" >> "$SUMMARY_CSV"
  done
  echo
done

# ---- Per-k summary statistics ----
echo "=== Per-k Summary ==="
awk -F, '
NR == 1 { next }
{
  k = $1;
  t = $3 + 0;
  p = $4 + 0;
  if (!(k in cnt)) { keys[++nk] = k }
  sum[k]  += t;
  sq[k]   += t * t;
  cnt[k]++;
  pred[k]  = p;
}
END {
  printf "%-8s %-14s %-14s %-14s %-10s\n",
    "k", "Mean(ms)", "Std(ms)", "Predicted(ms)", "Ratio";
  for (i = 1; i <= nk; i++) {
    k = keys[i];
    n = cnt[k];
    mean = sum[k] / n;
    var  = (sq[k] / n) - (mean * mean);
    if (var < 0) var = 0;
    std  = sqrt(var);
    ratio = mean / pred[k];
    printf "%-8s %-14.3f %-14.3f %-14.3f %-10.4f\n",
      k, mean, std, pred[k], ratio;
  }
}
' "$SUMMARY_CSV"

echo
echo "Raw per-call data : $RAW_CSV"
echo "Summary data      : $SUMMARY_CSV"
echo "Done."
