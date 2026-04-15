#!/usr/bin/env bash
# argon2id_attacker_kchain_sweep.sh
#
# 2-D attacker throughput table over Argon2id memory cost (m) and KDF
# chaining depth (k), modelling effective attacker throughput when the
# defender uses k-chain key derivation (Equation eq:kdf_chaining).
#
# Because each candidate requires k strictly sequential Argon2id evaluations
# (serial data dependency), the GPU cannot pipeline rounds within a single
# candidate.  Effective throughput therefore scales exactly as:
#
#   R(m, k) = R(m, 1) / k
#
# Strategy
# --------
# Phase 1 — Empirical k-linearity confirmation:
#   Run REPS hashcat benchmarks at the single reference tier REF_MIB (default
#   1024 MiB) to confirm that single-invocation throughput is stable.  This
#   validates the R(m,k) = R(m,1)/k formula at the reference point.
#
# Phase 2 — Full (m, k) table from existing per-tier CSVs:
#   For every other memory tier, read R(m,1) values from the pre-existing
#   per-tier CSV files (argon2_gpu_m<N>MiB.csv) that were collected during
#   the main attacker sweep.  Apply R(m,k) = R(m,1)/k analytically.
#   No additional GPU time is needed for these tiers.
#
# Output files (written to OUT_DIR):
#   attacker_kchain_ref_raw.csv  -- per-rep R(1) measurements at REF_MIB
#   attacker_kchain_summary.csv  -- full (mem_mib, k) table: R(1) and R(k) stats
#
# Usage:
#   bash argon2id_attacker_kchain_sweep.sh
#
# Override defaults via environment variables, e.g.:
#   REF_MIB=1024 K_LIST="1 3 10" REPS=20 bash argon2id_attacker_kchain_sweep.sh
#
# The full MEM_LIST is used only for Phase 2 (existing CSV lookup).
# All tiers need a corresponding argon2_gpu_m<N>MiB.csv in CSV_DIR.

set -euo pipefail

# ---- Config ---------------------------------------------------------------
# Set DERIVE_ONLY=0 to run an additional live hashcat benchmark at REF_MIB
# as a sanity-check.  Default is 1 — all GPU data already collected in the
# per-tier argon2_gpu_m*.csv files; R(m,k) = R(m,1)/k is derived from those.
DERIVE_ONLY="${DERIVE_ONLY:-1}"

# Reference memory tier for empirical k-linearity confirmation (Phase 1 only)
REF_MIB="${REF_MIB:-1024}"

# All memory tiers to include in the final (m, k) summary table.
# Phase 2 looks for argon2_gpu_m<N>MiB.csv in CSV_DIR for each tier.
MEM_LIST="${MEM_LIST:-64 128 256 512 1024 2048 4096 8192}"

# Chaining depths — powers of 2, mirror defender sweep
K_LIST="${K_LIST:-1 2 4 8 16 32 64}"

T_COST="${T_COST:-1}"
P_LANES="${P_LANES:-1}"
REPS="${REPS:-20}"
BENCH_RUNTIME="${BENCH_RUNTIME:-60}"   # seconds per hashcat run (Phase 1 only)
ARGON2_MODE="${ARGON2_MODE:-34000}"    # hashcat mode for Argon2id

OUT_DIR="${OUT_DIR:-.}"
# Directory containing the pre-existing argon2_gpu_m*.csv files
CSV_DIR="${CSV_DIR:-.}"

REF_RAW_CSV="${OUT_DIR}/attacker_kchain_ref_raw.csv"
SUMMARY_CSV="${OUT_DIR}/attacker_kchain_summary.csv"

read -r -a MEM_VALUES <<< "$MEM_LIST"
read -r -a K_VALUES   <<< "$K_LIST"

# ---- Dependency checks ----------------------------------------------------
if [[ "$DERIVE_ONLY" -eq 1 ]]; then
  for cmd in awk bc sort; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: Missing dependency: $cmd"; exit 1; }
  done
else
  for cmd in hashcat python3 awk bc sort; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: Missing dependency: $cmd"; exit 1; }
  done
fi

# ---- Temp files -----------------------------------------------------------
HASH_FILE=$(mktemp --suffix=.hash)
REP_FILE=$(mktemp)
trap 'rm -f "$HASH_FILE" "$REP_FILE" "${REP_FILE}.sorted"' EXIT

# ---- CSV headers ----------------------------------------------------------
echo "mem_mib,rep,r1_hs" > "$REF_RAW_CSV"
echo "mem_mib,k,reps,source,r1_mean_hs,r1_std_hs,r1_p50_hs,r1_p95_hs,rk_mean_hs,rk_std_hs,rk_p50_hs,rk_p95_hs" > "$SUMMARY_CSV"

# ---- Helper: percentile from sorted file (one value per line) -------------
percentile() {
  local pct="$1" file="$2" n idx
  n=$(wc -l < "$file")
  idx=$(echo "scale=0; (($pct * $n + 99) / 100)" | bc)
  (( idx < 1 )) && idx=1
  (( idx > n  )) && idx=$n
  sed -n "${idx}p" "$file"
}

# ---- Helper: extract hashcat throughput (H/s) from output -----------------
parse_speed() {
  local out="$1"
  local speed_line speed_val unit

  speed_line=$(echo "$out" | grep "Speed\.#" | tail -n 1)
  speed_val=$(echo  "$speed_line" | awk '{print $2}')
  unit=$(echo       "$speed_line" | awk '{print $3}')

  if [[ "$unit" == "kH/s" ]]; then
    speed_val=$(awk -v v="$speed_val" 'BEGIN {printf "%.6f", v * 1000}')
  elif [[ "$unit" == "MH/s" ]]; then
    speed_val=$(awk -v v="$speed_val" 'BEGIN {printf "%.6f", v * 1000000}')
  fi

  if [[ -n "${speed_val:-}" ]] && awk -v v="$speed_val" 'BEGIN {exit !(v+0 > 100)}'; then
    echo "$speed_val"; return
  fi

  # Fallback for slow memory-heavy tiers: derive from Progress line
  local done_cnt
  done_cnt=$(echo "$out" | grep "Progress.*:" | tail -n 1 | awk '{print $2}' | cut -d'/' -f1)
  [[ -z "${done_cnt:-}" ]] && { echo "FAIL"; return; }
  awk -v d="$done_cnt" -v t="$BENCH_RUNTIME" 'BEGIN { printf "%.6f", d / t }'
}

# ---- Helper: compute stats + write summary rows for one (mem_mib, source) -
# $1=mem_mib  $2=source_label  $3=file-of-r1-values  $4=ref_raw_csv (or "" to skip)
emit_summary_rows() {
  local mem_mib="$1" source="$2" data_file="$3" raw_csv="${4:-}"

  local n
  n=$(wc -l < "$data_file")
  (( n == 0 )) && { echo "  [WARN] No data for ${mem_mib} MiB — skipping"; return; }

  # Optionally append raw measurements to the ref raw CSV
  if [[ -n "$raw_csv" ]]; then
    local rep=0
    while IFS= read -r v; do
      rep=$(( rep + 1 ))
      echo "${mem_mib},${rep},${v}" >> "$raw_csv"
    done < "$data_file"
  fi

  local sum sum2 mean var std p50 p95
  sum=$(awk  '{s+=$1}    END{printf "%.6f",s}' "$data_file")
  sum2=$(awk '{s+=$1*$1} END{printf "%.6f",s}' "$data_file")
  mean=$(echo "scale=6; $sum / $n" | bc -l)
  var=$(echo  "scale=10; v=$sum2/$n-($mean*$mean); if(v<0)v=0; v" | bc -l)
  std=$(echo  "scale=6; sqrt($var)" | bc -l)

  sort -n "$data_file" > "${data_file}.sorted"
  p50=$(percentile 50 "${data_file}.sorted")
  p95=$(percentile 95 "${data_file}.sorted")
  rm -f "${data_file}.sorted"

  printf "  R(1): mean=%.4f  std=%.4f  p50=%.4f  p95=%.4f  H/s  [%s]\n" \
    "$mean" "$std" "$p50" "$p95" "$source"

  for k in "${K_VALUES[@]}"; do
    local rk_mean rk_std rk_p50 rk_p95
    rk_mean=$(echo "scale=6; $mean / $k" | bc -l)
    rk_std=$(echo  "scale=6; $std  / $k" | bc -l)
    rk_p50=$(echo  "scale=6; $p50  / $k" | bc -l)
    rk_p95=$(echo  "scale=6; $p95  / $k" | bc -l)
    echo "${mem_mib},${k},${n},${source},${mean},${std},${p50},${p95},${rk_mean},${rk_std},${rk_p50},${rk_p95}" \
      >> "$SUMMARY_CSV"
  done
}

# ==========================================================================
# Phase 1 — Empirical benchmark at REF_MIB to confirm k-linearity
# ==========================================================================
if [[ "$DERIVE_ONLY" -eq 1 ]]; then
  echo "=== Phase 1: SKIPPED (DERIVE_ONLY=1) — all tiers derived from existing CSVs ==="
  echo
else
  echo "=== Phase 1: Empirical R(1) benchmark at ${REF_MIB} MiB ==="
  echo "    $REPS hashcat runs x ${BENCH_RUNTIME}s each"
  echo "    (Set DERIVE_ONLY=1 to skip this and use existing CSVs for all tiers)"
  echo

  ref_kib=$(( REF_MIB * 1024 ))

  python3 - <<PYEOF > "$HASH_FILE"
import base64
salt = base64.b64encode(b'1234567890123456').decode().rstrip('=')
tag  = base64.b64encode(b'\x00' * 32).decode().rstrip('=')
print(f'\$argon2id\$v=19\$m=${ref_kib},t=${T_COST},p=${P_LANES}\${salt}\${tag}')
PYEOF

  workload=3
  (( REF_MIB >= 4096 )) && workload=1

  > "$REP_FILE"
  for rep in $(seq 1 "$REPS"); do
    HC_OUT=$(hashcat -m "$ARGON2_MODE" "$HASH_FILE" -a 3 '?b?b?b?b?b?b?b' \
               --runtime "$BENCH_RUNTIME" \
               --status --status-timer 1 \
               --self-test-disable \
               --potfile-disable \
               --backend-ignore-opencl \
               -D 2 -w "$workload" 2>&1 || true)

    if echo "$HC_OUT" | grep -q "Out of Device Memory"; then
      echo "  [CRITICAL] Out of VRAM — aborting Phase 1"; break
    fi

    speed=$(parse_speed "$HC_OUT")
    if [[ "$speed" == "FAIL" ]] || [[ -z "${speed:-}" ]]; then
      printf "  rep %2d/%d : FAILED\n" "$rep" "$REPS"; continue
    fi
    printf "  rep %2d/%d : %.4f H/s\n" "$rep" "$REPS" "$speed"
    echo "$speed" >> "$REP_FILE"
  done

  emit_summary_rows "$REF_MIB" "empirical" "$REP_FILE" "$REF_RAW_CSV"
fi

# ==========================================================================
# Phase 2 — Derive R(m,k) for all tiers from existing per-tier CSVs
# ==========================================================================
echo
echo "=== Phase 2: Deriving R(m,k) from existing per-tier CSVs in ${CSV_DIR} ==="
echo "    R(m,k) = R(m,1) / k  [exact, by serial data dependency]"
echo

TIER_FILE=$(mktemp)
trap 'rm -f "$HASH_FILE" "$REP_FILE" "$TIER_FILE" "${REP_FILE}.sorted" "${TIER_FILE}.sorted"' EXIT

for mem_mib in "${MEM_VALUES[@]}"; do
  # In normal mode skip REF_MIB — already handled empirically in Phase 1
  if [[ "$DERIVE_ONLY" -eq 0 ]] && [[ "$mem_mib" -eq "$REF_MIB" ]]; then continue; fi

  tier_csv="${CSV_DIR}/argon2_gpu_m${mem_mib}MiB.csv"
  if [[ ! -f "$tier_csv" ]]; then
    echo "  [WARN] ${tier_csv} not found — skipping ${mem_mib} MiB"
    continue
  fi

  echo "--- ${mem_mib} MiB  (source: $(basename "$tier_csv")) ---"

  # Extract HashRate_Hs column (column 5), skip header
  awk -F, 'NR>1 && $5+0>0 {print $5}' "$tier_csv" > "$TIER_FILE"

  emit_summary_rows "$mem_mib" "csv:$(basename "$tier_csv")" "$TIER_FILE"
done
rm -f "$TIER_FILE"

# ---- Console summary table ------------------------------------------------
echo
echo "=== Full (m, k) Throughput Table ==="
awk -F, '
NR==1 { next }
{
  printf "m=%-6s MiB  k=%-3s  R(1)=%10.4f H/s  R(k)=%10.4f H/s  [%s]\n",
    $1, $2, $5, $9, $4
}
' "$SUMMARY_CSV"

echo
echo "Reference raw : $REF_RAW_CSV"
echo "Summary       : $SUMMARY_CSV"
