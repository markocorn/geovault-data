#!/usr/bin/env bash
# argon2_cpu_sweep.sh
# CPU-only Argon2id latency sweep (ms/hash) over memory cost 2^m KiB.

set -euo pipefail

# -------- Params --------
MEXP_START="${1:-17}"   # e.g., 17 → 128 MiB
MEXP_END="${2:-20}"     # e.g., 20 → 1024 MiB
RUNS="${3:-20}"         # repetitions per m_exp

TYPE="id"               # Argon2id
T_COST=1                # time cost
P_LANES=1               # parallelism
HASHLEN=32              # tag length
PASSWORD="example-w3w-password"
SALT="example-w3w-salt"

SUMMARY_OUT="argon2_cpu_m${MEXP_START}_${MEXP_END}_r${RUNS}_summary.csv"
RAW_OUT="argon2_cpu_m${MEXP_START}_${MEXP_END}_r${RUNS}_raw.csv"

# -------- Deps --------
for cmd in argon2 bc date; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing: $cmd (install: sudo apt install argon2 bc coreutils)"; exit 1; }
done

(( MEXP_END >= MEXP_START )) || { echo "m_exp_end must be >= m_exp_start"; exit 1; }

# -------- CSV headers --------
[[ -f "$SUMMARY_OUT" ]] || echo "m_exp,mem_kib,mem_mib,t_cost,p_lanes,type,runs,avg_ms,std_ms" > "$SUMMARY_OUT"
[[ -f "$RAW_OUT"     ]] || echo "m_exp,mem_kib,mem_mib,run_idx,ms" > "$RAW_OUT"

echo "Argon2id CPU sweep: m=${MEXP_START}..${MEXP_END}, runs=${RUNS}, t=${T_COST}, p=${P_LANES}"

# -------- Sweep --------
for (( MEXP=MEXP_START; MEXP<=MEXP_END; MEXP++ )); do
  MEM_KiB=$((1 << MEXP))
  MEM_MiB=$((MEM_KiB / 1024))
  echo "m=${MEXP} (${MEM_MiB} MiB) …"

  total_ms=0
  total_ms2=0

  for ((i=1; i<=RUNS; i++)); do
    start_ns=$(date +%s%N)

    # Argon2 CLI computes and prints the hash; we discard output
    printf "%s" "$PASSWORD" | \
      argon2 "$SALT" \
        -$TYPE \
        -v 13 \
        -t "$T_COST" \
        -m "$MEXP" \
        -p "$P_LANES" \
        -l "$HASHLEN" \
        > /dev/null

    end_ns=$(date +%s%N)
    d_ns=$((end_ns - start_ns))

    # ns → ms (float)
    ms=$(echo "scale=6; $d_ns / 1000000" | bc -l)

    total_ms=$(echo "$total_ms + $ms" | bc -l)
    ms2=$(echo "$ms * $ms" | bc -l)
    total_ms2=$(echo "$total_ms2 + $ms2" | bc -l)

    # raw line
    printf "%d,%d,%d,%d,%.6f\n" "$MEXP" "$MEM_KiB" "$MEM_MiB" "$i" "$ms" >> "$RAW_OUT"

    # light progress
    if (( i % 10 == 0 )); then echo "  run $i/$RUNS"; fi
  done

  mean=$(echo "scale=6; $total_ms / $RUNS" | bc -l)
  mean2=$(echo "scale=6; $total_ms2 / $RUNS" | bc -l)
  var=$(echo "scale=10; v = $mean2 - ($mean * $mean); if (v < 0) v = 0; v" | bc -l)
  std=$(echo "scale=6; sqrt($var)" | bc -l)

  printf "  avg=%.3f ms  std=%.3f ms\n" "$mean" "$std"

  printf "%d,%d,%d,%d,%d,%s,%d,%.6f,%.6f\n" \
    "$MEXP" "$MEM_KiB" "$MEM_MiB" "$T_COST" "$P_LANES" "$TYPE" "$RUNS" "$mean" "$std" >> "$SUMMARY_OUT"
done

echo "Done."
echo "Summary: $SUMMARY_OUT"
echo "Raw    : $RAW_OUT"
