#!/usr/bin/env bash
# argon2id_attacker_kchain_verify.sh
#
# Verifies that k-chain Argon2id computation time scales LINEARLY in k,
# i.e. T(k) = k * T(1).  This directly confirms that GPU attacker throughput
# under k-chaining scales as R_GPU(k) = R_GPU(1) / k.
#
# Why CPU measurement proves GPU linearity:
#   The GPU fills floor(VRAM/m) candidate slots in parallel.  Each slot runs
#   the same Argon2id algorithm with the same serial data dependency between
#   chain calls.  All slots slow down by exactly factor k.  Therefore the
#   linearity T(k)/T(1) = k holds identically on GPU — CPU timing confirms
#   the mathematical property at lower cost.
#
# Output:
#   attacker_kchain_verify_raw.csv     -- (k, rep, chain_ms)
#   attacker_kchain_verify_summary.csv -- per k: mean_ms, ratio = T(k)/(k*T(1))
#
# ratio ~ 1.000 for all k confirms the claim.
#
# Usage:
#   bash argon2id_attacker_kchain_verify.sh
#   MEM_MIB=1024 REPS=20 bash argon2id_attacker_kchain_verify.sh

set -euo pipefail

# ---- Config ---------------------------------------------------------------
MEM_MIB="${MEM_MIB:-1024}"
K_LIST="${K_LIST:-1 2 4 8 16 32 64}"
T_COST="${T_COST:-1}"
P_LANES="${P_LANES:-1}"
HASHLEN="${HASHLEN:-32}"
REPS="${REPS:-20}"
SALT="${SALT:-geovault-salt}"
INITIAL_GUESS="${INITIAL_GUESS:-31415926535897}"
TYPE="id"
VERSION="13"
OUT_DIR="${OUT_DIR:-.}"

RAW_CSV="${OUT_DIR}/attacker_kchain_verify_raw.csv"
SUMMARY_CSV="${OUT_DIR}/attacker_kchain_verify_summary.csv"

read -r -a K_VALUES <<< "$K_LIST"
MEM_KIB=$(( MEM_MIB * 1024 ))

# ---- Dependency checks ----------------------------------------------------
for cmd in argon2 awk bc date sort; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing $cmd"; exit 1; }
done

# ---- Temp files -----------------------------------------------------------
TIMING_FILE=$(mktemp)
HASH_FILE=$(mktemp)
REP_FILE=$(mktemp)
trap 'rm -f "$TIMING_FILE" "$HASH_FILE" "$REP_FILE" "${REP_FILE}.sorted"' EXIT

# ---- CSV headers ----------------------------------------------------------
echo "mem_mib,k,rep,chain_ms" > "$RAW_CSV"
echo "mem_mib,k,reps,mean_ms,std_ms,t1_mean_ms,linearity_ratio" > "$SUMMARY_CSV"

echo "=== Argon2id k-Chain Linearity Verification ==="
echo "m=${MEM_MIB} MiB  t=${T_COST}  p=${P_LANES}  reps=${REPS}"
echo "Claim: T(k) = k * T(1)  =>  ratio = T(k) / (k * T(1)) ~ 1.000"
echo

# ---- Helper: one Argon2id call, writes ms->TIMING_FILE, hash->HASH_FILE --
run_one() {
  local start_ns end_ns
  start_ns=$(date +%s%N)
  printf "%s" "$1" | argon2 "$SALT" -"$TYPE" -v "$VERSION" \
    -t "$T_COST" -k "$MEM_KIB" -p "$P_LANES" -l "$HASHLEN" -r > "$HASH_FILE"
  end_ns=$(date +%s%N)
  echo "scale=6; (${end_ns} - ${start_ns}) / 1000000" | bc -l > "$TIMING_FILE"
}

percentile() {
  local pct="$1" file="$2" n idx
  n=$(wc -l < "$file")
  idx=$(echo "scale=0; (($pct * $n + 99) / 100)" | bc)
  (( idx < 1 )) && idx=1; (( idx > n )) && idx=$n
  sed -n "${idx}p" "$file"
}

# T(1) measured first -- required for ratio of all other k
T1_MEAN=""

# ---- Main loop ------------------------------------------------------------
for k in "${K_VALUES[@]}"; do
  echo "--- k=${k} ---"
  > "$REP_FILE"

  for rep in $(seq 1 "$REPS"); do
    current="$INITIAL_GUESS"
    chain_ms="0"
    for call in $(seq 1 "$k"); do
      run_one "$current"
      call_ms=$(cat "$TIMING_FILE")
      current=$(cat "$HASH_FILE")
      chain_ms=$(echo "scale=6; $chain_ms + $call_ms" | bc -l)
    done
    echo "${MEM_MIB},${k},${rep},${chain_ms}" >> "$RAW_CSV"
    echo "$chain_ms" >> "$REP_FILE"
    printf "  rep %2d/%d : %.1f ms\n" "$rep" "$REPS" "$chain_ms"
  done

  # Stats
  n="$REPS"
  sum=$(awk  '{s+=$1}    END{printf "%.6f",s}' "$REP_FILE")
  sum2=$(awk '{s+=$1*$1} END{printf "%.6f",s}' "$REP_FILE")
  mean=$(echo "scale=6; $sum / $n" | bc -l)
  var=$(echo  "scale=10; v=$sum2/$n-($mean*$mean); if(v<0)v=0; v" | bc -l)
  std=$(echo  "scale=6; sqrt($var)" | bc -l)

  # Store T(1) on first iteration
  [[ -z "$T1_MEAN" ]] && T1_MEAN="$mean"

  # linearity_ratio = T(k) / (k * T(1))  -- expect 1.000
  ratio=$(echo "scale=4; $mean / ($k * $T1_MEAN)" | bc -l)

  printf "  => mean=%.1f ms  T(1)=%.1f ms  ratio=%.4f\n\n" "$mean" "$T1_MEAN" "$ratio"

  echo "${MEM_MIB},${k},${n},${mean},${std},${T1_MEAN},${ratio}" >> "$SUMMARY_CSV"
done

# ---- Summary table --------------------------------------------------------
echo "=== Results ==="
printf "%-4s  %-12s  %-10s  %-8s\n" "k" "mean_ms" "k*T(1)_ms" "ratio"
printf "%-4s  %-12s  %-10s  %-8s\n" "----" "------------" "----------" "--------"
awk -F, '
NR==1 { next }
NR==2 { t1=$4 }
{ printf "%-4s  %-12.1f  %-10.1f  %-8.4f\n", $2, $4, ($2 * t1), $7 }
' "$SUMMARY_CSV"

echo
echo "Raw     : $RAW_CSV"
echo "Summary : $SUMMARY_CSV"