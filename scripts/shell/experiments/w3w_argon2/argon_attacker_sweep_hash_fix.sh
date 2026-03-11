#!/usr/bin/env bash
# argon2_smart_sweep.sh
# Performs multiple runs of the "Smart Benchmark" logic.
# Saves exact speed of each run to CSV.

set -u

# ──────────────── Config ────────────────
RUNS=100                  # Number of times to repeat the test
TARGET=300               # Stop after reaching this many hashes
MEM_MIB=8192            # 8 GB
ARGON2_MODE="34000"
OUT_CSV="argon2_gpu_8gb_smart_results.csv"
# ────────────────────────────────────────

echo "=== Argon2id Smart Sweep (8GB) ==="
echo "Target:   At least $TARGET hashes per run"
echo "Runs:     $RUNS"
echo "Output:   $OUT_CSV"
echo "--------------------------------------"

# Initialize CSV with headers
echo "Run,Target_Hashes,Actual_Hashes,Time_Seconds,Speed_Hs" > "$OUT_CSV"

for run in $(seq 1 "$RUNS"); do
    echo ">>> Starting Run $run/$RUNS..."

    # 1. Generate hash (Pure Bash)
    SALT=$(printf '1234567890123456' | base64 | tr -d '=')
    TAG=$(printf '\0%.0s' {1..32} | base64 | tr -d '=')
    MEM_KIB=$((MEM_MIB * 1024))
    HASHFILE=$(mktemp --suffix=.hash)
    printf "\$argon2id\$v=19\$m=%d,t=1,p=1\$%s\$%s\n" "$MEM_KIB" "$SALT" "$TAG" > "$HASHFILE"

    # 2. Run Hashcat in Background
    start_time=$(date +%s.%N)
    LOGFILE=$(mktemp)

    # Start hashcat silently
    hashcat -m "$ARGON2_MODE" "$HASHFILE" -a 3 ?b?b?b?b?b?b?b \
        --status --status-timer 1 \
        --self-test-disable --potfile-disable --backend-ignore-opencl \
        -D 2 -w 1 > "$LOGFILE" 2>&1 &

    HC_PID=$!

    # 3. Monitor Loop
    final_count=0
    end_time=0

    while true; do
        # Safety check: if process died unexpectedly
        if ! kill -0 $HC_PID 2>/dev/null; then
            echo "  [WARNING] Hashcat died unexpectedly."
            break
        fi

        # Check log for progress
        line=$(grep "Progress" "$LOGFILE" | tail -n 1)

        if [ -n "$line" ]; then
            # Extract number
            current=$(echo "$line" | sed -E 's/.*Progress[^:]*: ([0-9]+)\/.*/\1/')

            # Show live status on same line
            echo -ne "  [Run $run] Progress: $current hashes... \r"

            # STOP CONDITION
            if [ "$current" -ge "$TARGET" ]; then
                echo ""
                # Kill cleanly
                kill $HC_PID 2>/dev/null
                wait $HC_PID 2>/dev/null

                final_count=$current
                end_time=$(date +%s.%N)
                break
            fi
        fi
        sleep 1
    done

    # Fallback if loop broke without setting end_time
    if [ "$end_time" == "0" ]; then
        end_time=$(date +%s.%N)
        final_count=$(grep "Progress" "$LOGFILE" | tail -n 1 | sed -E 's/.*Progress[^:]*: ([0-9]+)\/.*/\1/')
        [ -z "$final_count" ] && final_count=0
    fi

    # 4. Calculate
    LC_NUMERIC=C
    duration=$(echo "$end_time - $start_time" | bc -l)

    if (( $(echo "$duration > 0" | bc -l) )); then
        speed=$(echo "$final_count / $duration" | bc -l)
    else
        speed=0
    fi

    # Format
    duration_fmt=$(printf "%.4f" "$duration")
    speed_fmt=$(printf "%.4f" "$speed")

    echo "  -> Result: $speed_fmt H/s ($final_count hashes in ${duration_fmt}s)"

    # Save to CSV
    echo "${run},${TARGET},${final_count},${duration_fmt},${speed_fmt}" >> "$OUT_CSV"

    # Cleanup
    rm "$HASHFILE" "$LOGFILE"

    # Cool down pause (optional)
    sleep 2
done

echo "--------------------------------------"
echo "Sweep Complete. Results saved to $OUT_CSV"