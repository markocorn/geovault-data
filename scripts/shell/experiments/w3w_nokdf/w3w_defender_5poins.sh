#!/bin/bash
# defender_sha256_cumulative_points.sh
# Benchmark SHA-256 vs input length by concatenating "points":
#   1 point  -> token1
#   2 points -> token1.token2
#   3 points -> token1.token2.token3
#   ...
# Uses 14-digit decimal tokens (~46.5 bits each) to approximate w3w-cell entropy.
#
# Output CSV columns:
#   Run,Points,InputLen_bytes,Time_ms

set -euo pipefail

# ---- Config ----
RUNS=10000
POINT_COUNTS=(1 2 3 4 5)
DELIM="."   # delimiter between tokens (like w3w uses dots)

# 14-digit decimal tokens (~46.5 bits each). Replace with any fixed values you want.
TOKENS=(
  "31415926535897"
  "27182818284590"
  "16180339887498"
  "14142135623730"
  "17320508075688"
)

OUT_PREFIX="defender_sha256_cumulative"

# ---- Dependency checks ----
for cmd in openssl awk bc wc; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    exit 1
  fi
done

# ---- Sanity check ----
max_points=0
for p in "${POINT_COUNTS[@]}"; do
  (( p > max_points )) && max_points=$p
done
if ((${#TOKENS[@]} < max_points)); then
  echo "Error: Need at least $max_points TOKENS entries, but only have ${#TOKENS[@]}."
  exit 1
fi

echo "=== Defender Benchmark: SHA-256 (CPU, OpenSSL) ==="
echo "Runs per setting : $RUNS"
echo "Point counts     : ${POINT_COUNTS[*]}"
echo "Token format     : 14-digit decimal (~46.5 bits each)"
echo "Delimiter        : '$DELIM'"
echo

build_input() {
  local points="$1"
  local s="${TOKENS[0]}"
  for ((i=1; i<points; i++)); do
    s+="${DELIM}${TOKENS[i]}"
  done
  printf "%s" "$s"
}

benchmark_points() {
  local points="$1"
  local out_csv="${OUT_PREFIX}_${points}points_raw.csv"

  local input
  input="$(build_input "$points")"
  local input_len
  # bytes (no newline)
  input_len=$(printf "%s" "$input" | wc -c | awk '{print $1}')

  echo "Benchmarking $points point(s): input_len=${input_len} bytes"
  echo "Output CSV: $out_csv"
  echo "Run,Points,InputLen_bytes,Time_ms" > "$out_csv"

  for i in $(seq 1 "$RUNS"); do
    START=$(date +%s%N)

    # ONE SHA-256 per run, on the cumulative string
    printf "%s" "$input" | openssl dgst -sha256 -binary > /dev/null

    END=$(date +%s%N)
    DIFF_NS=$((END - START))
    DIFF_MS=$(echo "scale=9; $DIFF_NS / 1000000" | bc -l)

    echo "$i,$points,$input_len,$DIFF_MS" >> "$out_csv"
  done

  # ---- Stats (printed only) ----
  awk -F, -v points="$points" -v ilen="$input_len" '
    NR > 1 {
      sum += $4;
      sq  += $4*$4;
      n++;
    }
    END {
      mean = sum/n;
      std  = sqrt((sq/n) - (mean*mean));
      tps  = 1000/mean;

      printf "\n--- Results (%d point(s), input %d bytes) ---\n", points, ilen;
      printf "Sample Size (N)         : %d\n", n;
      printf "Average Time (Mean)     : %12.9f ms\n", mean;
      printf "Standard Deviation      : %12.9f ms\n", std;
      printf "Throughput              : %12.2f hashes/second\n", tps;
    }
  ' "$out_csv"

  echo
}

for points in "${POINT_COUNTS[@]}"; do
  benchmark_points "$points"
done

echo "All benchmarks complete."
