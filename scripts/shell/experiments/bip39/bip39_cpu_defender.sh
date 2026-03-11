#!/bin/bash
# bip39-cpu.sh
# Benchmarking the Defender cost: Standard CPU PBKDF2 performance.
# Uses OpenSSL for crypto and AWK for statistics (No Python).

set -euo pipefail

MNEMONIC="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
SALT="mnemonic"
RUNS=10000
OUT_CSV="bip39_cpu_raw_results.csv"

# ---- Dependency checks ----
for cmd in openssl awk bc lscpu; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    exit 1
  fi
done

echo "=== BIP-39 Defender Benchmark: CPU Only (OpenSSL) ==="
echo "Hardware: $(lscpu | grep 'Model name' | awk -F: '{print $2}' | xargs)"
echo "Saving raw data to: $OUT_CSV"
echo "Run,Time_ms" > "$OUT_CSV"

echo "Measuring $RUNS runs..."

# 1. Benchmark Loop
for i in $(seq 1 "$RUNS"); do
  # Measure time in nanoseconds
  START=$(date +%s%N)

  # Perform BIP39 PBKDF2 (HMAC-SHA512, 2048 iterations, 64-byte output)
  echo -n "$MNEMONIC" | \
  openssl enc -pbkdf2 -iter 2048 -md sha512 -salt -pass stdin -out /dev/null


  END=$(date +%s%N)

  # Calculate delta in milliseconds
  DIFF_NS=$((END - START))
  DIFF_MS=$(echo "scale=9; $DIFF_NS / 1000000" | bc -l)

  echo "$i,$DIFF_MS" >> "$OUT_CSV"
done

# 2. Calculate Statistics using AWK
STATS=$(awk -F, '
    NR > 1 {
        sum += $2;
        sq_sum += $2 * $2;
        count++;
    }
    END {
        if (count > 0) {
            mean = sum / count;
            std = sqrt((sq_sum / count) - (mean * mean));
            printf "%.6f|%.6f", mean, std;
        }
    }
' "$OUT_CSV")

AVG_MS=$(echo "$STATS" | cut -d'|' -f1)
STD_MS=$(echo "$STATS" | cut -d'|' -f2)
TPS=$(echo "scale=2; 1000 / $AVG_MS" | bc -l)

echo
echo "--- Results (BIP-39 Cost: 2048 Iterations) ---"
printf "Average Time (Mean)   : %10.6f ms\n" "$AVG_MS"
printf "Standard Deviation    : %10.6f ms\n" "$STD_MS"
printf "Throughput            : %10.2f checks/second\n" "$TPS"
echo "CSV export complete: $OUT_CSV"