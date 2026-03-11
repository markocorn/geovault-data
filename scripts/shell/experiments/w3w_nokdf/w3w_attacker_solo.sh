#!/bin/bash
# w3w_attacker_sha256_gpu_fixed.sh

set -euo pipefail

# ---- Config ----
RUNS=3
RUNTIME_S=60
HASH_MODE=1400
POINT_COUNTS=(1 2 3 4 5)
DIGITS_PER_POINT=14
DELIM="."
OUT_PREFIX="attacker_sha256_gpu_len_sensitive"

# Removed --backend-ignore-cpu to ensure OpenCL platforms are found correctly
# Added --force to skip potential warning blocks
HASHCAT_BASE=(hashcat -m "$HASH_MODE" -a 0 -D 2 --force)
HASHCAT_OPTS=(
  --potfile-disable
  --restore-disable
  --hwmon-disable
  --status
  --status-timer=5
  --runtime "$RUNTIME_S"
  -w 4
)

# Check dependencies
for cmd in hashcat mp64 awk grep sed openssl tr tail; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing dependency: $cmd"; exit 1; }
done

# Prepare Target
TARGET_PLAINTEXT="NOT_IN_KEYSPACE_abcdef"
TARGET_HASH_HEX="$(printf "%s" "$TARGET_PLAINTEXT" | openssl dgst -sha256 | awk '{print $2}')"
HASHFILE="target_sha256.hash"
echo "$TARGET_HASH_HEX" > "$HASHFILE"

echo "=== Attacker Benchmark: GPU SHA-256 (Pipe Mode) ==="
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader || true

# Function to parse logs
parse_speed() {
    local logfile="$1"
    # Extract lines containing "Speed.#"
    # We use 'tr' to clean up Windows-style line endings if present
    local speed_data
    speed_data=$(tr -d '\r' < "$logfile" | grep "Speed.#" || true)

    if [ -z "$speed_data" ]; then
        echo "0,0,ERROR_NO_SPEED_DATA"
        return
    fi

    echo "$speed_data" | awk '
    function mult(u) {
        if (u ~ /GH\/s/) return 1e9;
        if (u ~ /MH\/s/) return 1e6;
        if (u ~ /kH\/s/) return 1e3;
        return 1;
    }
    {
        # Typical line: Speed.#1.........:  5341.2 MH/s (51.21ms) @ Accel:128 Loops:1024 Thr:64 Vec:1
        for(i=1; i<=NF; i++) {
            if ($i ~ /[0-9.]+/ && $(i+1) ~ /H\/s/) {
                val = $i
                unit = $(i+1)
                sum += val * mult(unit)
                count++
            }
        }
    }
    END {
        if (count > 0) printf "%.0f,%d,SUCCESS\n", sum/count, count;
        else printf "0,0,PARSE_FAILURE\n";
    }'
}

for points in "${POINT_COUNTS[@]}"; do
    ILEN=$((points * DIGITS_PER_POINT + (points - 1)))

    # Build mask for mp64
    MASK="?d?d?d?d?d?d?d?d?d?d?d?d?d?d"
    for ((p=2; p<=points; p++)); do
        MASK+="${DELIM}?d?d?d?d?d?d?d?d?d?d?d?d?d?d"
    done

    OUT_CSV="${OUT_PREFIX}_${points}points_raw.csv"
    echo "Run,Points,InputLen,HashRate,StatusLines,Mask" > "$OUT_CSV"

    echo "--- Benchmarking $points Points (Length: $ILEN) ---"

    for i in $(seq 1 "$RUNS"); do
        LOGFILE="hashcat_p${points}_r${i}.log"

        echo "  [Run $i] Starting Hashcat..."

        # We pipe mp64 directly into hashcat.
        # mp64 produces the candidates, hashcat reads them from stdin (-a 0)
        set +e
        mp64 "$MASK" | "${HASHCAT_BASE[@]}" "${HASHCAT_OPTS[@]}" "$HASHFILE" > "$LOGFILE" 2>&1
        set -e

        # Parse results
        RESULTS=$(parse_speed "$LOGFILE")
        HASHRATE=$(echo "$RESULTS" | cut -d, -f1)
        SLINES=$(echo "$RESULTS" | cut -d, -f2)

        echo "  [Run $i] Result: $HASHRATE H/s ($SLINES status updates)"
        echo "$i,$points,$ILEN,$HASHRATE,$SLINES,$MASK" >> "$OUT_CSV"
    done
    echo ""
done

echo "Benchmark Complete."