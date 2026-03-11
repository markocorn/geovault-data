#!/usr/bin/env bash
# w3w_defender_argon2id_cpu_sweep.sh

set -euo pipefail

# ---- Config ----
RUNS="${RUNS:-10}"
INPUT_SECRET="${INPUT_SECRET:-31415926535897}"
SALT="${SALT:-geovault-salt}"

TYPE="id"
VERSION="13"
T_COST="${T_COST:-1}"
P_LANES="${P_LANES:-1}"
HASHLEN="${HASHLEN:-32}"

# FIXED: Ensure this is parsed as an array even if passed as an environment variable
if [[ -n "${MEM_MIB_LIST:-}" && ! "${MEM_MIB_LIST}" =~ "(" ]]; then
    # If passed as "64 128 256" via CLI, convert to array
    read -r -a MEM_MIB_LIST <<< "${MEM_MIB_LIST}"
else
    # Default array assignment
    MEM_MIB_LIST=(16384 32768) # 2GB, 4GB, 8GB, 16GB, 32GB
fi

OUT_PREFIX="${OUT_PREFIX:-defender_argon2id_cpu}"

# ---- Dependency checks ----
for cmd in argon2 awk bc date; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing dependency: $cmd"; exit 1; }
done

echo "=== Defender Benchmark: Argon2id (CPU, argon2 CLI) ==="
echo "Runs per setting : $RUNS"
echo "t_cost           : $T_COST"
echo "p_lanes          : $P_LANES"
echo "memory sweep     : ${MEM_MIB_LIST[*]} MiB"
echo

# ---- Helper: run one KDF and time it ----
time_one_argon2() {
  local mem_mib="$1"
  local start_ns end_ns diff_ns diff_ms

  # Use %s%N for nanoseconds (Linux/Coreutils)
  start_ns=$(date +%s%N)

  # Calculate KiB safely
  local mem_kib=$(( mem_mib * 1024 ))

  printf "%s" "$INPUT_SECRET" | \
    argon2 "$SALT" \
      -"$TYPE" \
      -v "$VERSION" \
      -t "$T_COST" \
      -k "$mem_kib" \
      -p "$P_LANES" \
      -l "$HASHLEN" \
      > /dev/null

  end_ns=$(date +%s%N)
  diff_ns=$((end_ns - start_ns))
  # bc handles the floating point math
  diff_ms=$(echo "scale=9; $diff_ns / 1000000" | bc -l)
  printf "%s" "$diff_ms"
}

# ---- Main sweep ----
for mem_mib in "${MEM_MIB_LIST[@]}"; do
  # Use quotes to ensure the filename doesn't break if there are spaces
  OUT_CSV="${OUT_PREFIX}_m${mem_mib}MiB_raw.csv"

  echo "Benchmarking memory: ${mem_mib} MiB"
  echo "Output CSV: $OUT_CSV"
  echo "Run,Time_ms" > "$OUT_CSV"

  for i in $(seq 1 "$RUNS"); do
    ms="$(time_one_argon2 "$mem_mib")"
    echo "${i},${ms}" >> "$OUT_CSV"

    if (( i % 25 == 0 )); then
      echo "  run $i/$RUNS"
    fi
  done

  # ---- Stats (AWK) ----
  STATS=$(awk -F, '
    NR > 1 {
      sum += $2;
      sq  += $2*$2;
      n++;
    }
    END {
      if (n>0) {
        mean = sum/n;
        var  = (sq/n) - (mean*mean);
        if (var < 0) var = 0;
        std  = sqrt(var);
        printf "%.9f|%.9f", mean, std;
      }
    }
  ' "$OUT_CSV")

  AVG_MS=$(echo "$STATS" | cut -d'|' -f1)
  STD_MS=$(echo "$STATS" | cut -d'|' -f2)
  TPS=$(echo "scale=6; 1000 / $AVG_MS" | bc -l)

  echo "--- Results (${mem_mib} MiB) ---"
  printf "Average Time (Mean)     : %12.9f ms\n" "$AVG_MS"
  printf "Standard Deviation      : %12.9f ms\n" "$STD_MS"
  printf "Throughput              : %12.6f KDFs/second\n" "$TPS"
  echo
done

echo "All KDF benchmarks complete."