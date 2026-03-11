#!/bin/bash
# w3w_defender_sha256_cpu.sh
# Defender benchmark for What3Words (single cell, no KDF):
#   - Measures SHA-256 cost using standard system crypto (OpenSSL)
#   - One SHA-256 per run, timed with wall-clock
#   - Exports raw CSV + mean/std + throughput
#
# Output CSV columns:
#   Run,Time_ms

set -euo pipefail

# ---- Config ----
W3W_CELL="filled.count.soap"        # example single W3W cell (3 words). Replace with any string.
RUNS=10000
OUT_CSV="w3w_defender_sha256_raw_results.csv"

# ---- Dependency checks ----
for cmd in openssl awk bc; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    exit 1
  fi
done

echo "=== W3W Defender Benchmark: SHA-256 (CPU, OpenSSL) ==="
echo "Input (single cell): $W3W_CELL"
echo "Saving raw data to:  $OUT_CSV"
echo "Run,Time_ms" > "$OUT_CSV"
echo "Measuring $RUNS runs..."
echo

# 1) Benchmark loop
for i in $(seq 1 "$RUNS"); do
  START=$(date +%s%N)

  # One SHA-256 evaluation using system library (OpenSSL)
  # -binary avoids hex formatting overhead; output discarded
  printf "%s" "$W3W_CELL" | openssl dgst -sha256 -binary > /dev/null

  END=$(date +%s%N)

  DIFF_NS=$((END - START))
  DIFF_MS=$(echo "scale=9; $DIFF_NS / 1000000" | bc -l)

  echo "$i,$DIFF_MS" >> "$OUT_CSV"
done

# 2) Stats (AWK)
STATS=$(awk -F, '
  NR > 1 {
    sum += $2;
    sq  += $2*$2;
    n++;
  }
  END {
    if (n>0) {
      mean = sum/n;
      std  = sqrt((sq/n) - (mean*mean));
      printf "%.9f|%.9f", mean, std;
    }
  }
' "$OUT_CSV")

AVG_MS=$(echo "$STATS" | cut -d'|' -f1)
STD_MS=$(echo "$STATS" | cut -d'|' -f2)
TPS=$(echo "scale=2; 1000 / $AVG_MS" | bc -l)

echo "--- Results (SHA-256, standard library) ---"
printf "Sample Size (N)         : %d\n" "$RUNS"
printf "Average Time (Mean)     : %12.9f ms\n" "$AVG_MS"
printf "Standard Deviation      : %12.9f ms\n" "$STD_MS"
printf "Throughput              : %12.2f hashes/second\n" "$TPS"
echo "CSV export complete: $OUT_CSV"
