##!/usr/bin/env bash
## argon2_16g_fixed_sweep.sh
## Correctly sweeps 16GB tier using FORCE flags to prevent timeouts.
#
#set -u
#
## ──────────────── Config ────────────────
#RUNS=3                   # 3 runs is enough for stable data
#TARGET=5                 # 5 hashes is enough (~40-60 seconds)
#MEM_MIB=16384            # 16 GB
#ARGON2_MODE="34000"
#OUT_CSV="argon2_gpu_16G_fixed.csv"
## ────────────────────────────────────────
#
#echo "=== Argon2id 16GB Fixed Sweep ==="
#echo "Target:   $TARGET hashes per run"
#echo "Output:   $OUT_CSV"
#echo "Note:     Screen WILL freeze during runs."
#echo "--------------------------------------"
#
#echo "Run,Mem_MiB,Target_Hashes,Actual_Hashes,Time_Seconds,Speed_Hs" > "$OUT_CSV"
#
#for run in $(seq 1 "$RUNS"); do
#    echo ">>> Starting Run $run/$RUNS..."
#
#    # 1. Generate hash
#    SALT=$(printf '1234567890123456' | base64 | tr -d '=')
#    TAG=$(printf '\0%.0s' {1..32} | base64 | tr -d '=')
#    MEM_KIB=$((MEM_MIB * 1024))
#    HASHFILE=$(mktemp --suffix=.hash)
#    printf "\$argon2id\$v=19\$m=%d,t=1,p=1\$%s\$%s\n" "$MEM_KIB" "$SALT" "$TAG" > "$HASHFILE"
#
#    # 2. Run Hashcat with FORCE flags
#    start_time=$(date +%s.%N)
#    LOGFILE=$(mktemp)
#
#    # CRITICAL FIX: Added --force and --backend-devices-keepfree=1
#    hashcat -m "$ARGON2_MODE" "$HASHFILE" -a 3 ?b?b?b?b?b?b?b \
#        --status --status-timer 5 \
#        --self-test-disable --potfile-disable --backend-ignore-opencl \
#        --backend-devices-keepfree=1 \
#        --force \
#        -D 2 -w 1 > "$LOGFILE" 2>&1 &
#
#    HC_PID=$!
#
#    # 3. Monitor Loop
#    final_count=0
#    end_time=0
#
#    while true; do
#        if ! kill -0 $HC_PID 2>/dev/null; then
#            echo "  [WARNING] Hashcat stopped."
#            break
#        fi
#
#        line=$(grep "Progress" "$LOGFILE" | tail -n 1)
#
#        if [ -n "$line" ]; then
#            current=$(echo "$line" | sed -E 's/.*Progress[^:]*: ([0-9]+)\/.*/\1/')
#            echo -ne "  [Run $run] Progress: $current / $TARGET ... \r"
#
#            if [ "$current" -ge "$TARGET" ]; then
#                echo ""
#                kill $HC_PID 2>/dev/null
#                wait $HC_PID 2>/dev/null
#                final_count=$current
#                end_time=$(date +%s.%N)
#                break
#            fi
#        fi
#        sleep 2
#    done
#
#    # Fallback timing
#    if [ "$end_time" == "0" ]; then end_time=$(date +%s.%N); fi
#    if [ "$final_count" -eq 0 ]; then
#        final_count=$(grep "Progress" "$LOGFILE" | tail -n 1 | sed -E 's/.*Progress[^:]*: ([0-9]+)\/.*/\1/')
#        [ -z "$final_count" ] && final_count=0
#    fi
#
#    # 4. Calculate
#    LC_NUMERIC=C
#    duration=$(echo "$end_time - $start_time" | bc -l)
#
#    # Avoid div/0
#    if (( $(echo "$duration > 0" | bc -l) )); then
#        speed=$(echo "$final_count / $duration" | bc -l)
#    else
#        speed=0
#    fi
#
#    duration_fmt=$(printf "%.4f" "$duration")
#    speed_fmt=$(printf "%.4f" "$speed")
#
#    echo "  -> Result: $speed_fmt H/s ($final_count hashes in ${duration_fmt}s)"
#    echo "${run},${MEM_MIB},${TARGET},${final_count},${duration_fmt},${speed_fmt}" >> "$OUT_CSV"
#
#    rm "$HASHFILE" "$LOGFILE"
#    sleep 5 # Cool down
#done
#
#echo "Done. Results in $OUT_CSV"

#!/usr/bin/env bash
# argon2_32g_fixed_sweep.sh
# Benchmarks 32GB Argon2id.
# WARNING: This will freeze your GPU for 30+ seconds per hash.

set -u

# ──────────────── Config ────────────────
RUNS=3                   # 3 runs is plenty for this speed
TARGET=2                 # Only 2 hashes! (It is very slow)
MEM_MIB=32768            # 32 GB
ARGON2_MODE="34000"
OUT_CSV="argon2_gpu_32G_fixed.csv"
# ────────────────────────────────────────

echo "=== Argon2id 32GB Extreme Benchmark ==="
echo "Target:   $TARGET hashes per run"
echo "Memory:   $MEM_MIB MiB"
echo "WARNING:  Your screen WILL FREEZE for long periods. Do not panic."
echo "--------------------------------------"

echo "Run,Mem_MiB,Target_Hashes,Actual_Hashes,Time_Seconds,Speed_Hs" > "$OUT_CSV"

for run in $(seq 1 "$RUNS"); do
    echo ">>> Starting Run $run/$RUNS..."

    # 1. Generate hash
    SALT=$(printf '1234567890123456' | base64 | tr -d '=')
    TAG=$(printf '\0%.0s' {1..32} | base64 | tr -d '=')
    MEM_KIB=$((MEM_MIB * 1024))
    HASHFILE=$(mktemp --suffix=.hash)
    printf "\$argon2id\$v=19\$m=%d,t=1,p=1\$%s\$%s\n" "$MEM_KIB" "$SALT" "$TAG" > "$HASHFILE"

    # 2. Run Hashcat with FORCE flags
    start_time=$(date +%s.%N)
    LOGFILE=$(mktemp)

    # Flags:
    # --backend-devices-keepfree=1: Essential. Don't let OS reserve RAM.
    # --force: Essential. Bypass driver timeout panic.
    hashcat -m "$ARGON2_MODE" "$HASHFILE" -a 3 ?b?b?b?b?b?b?b \
        --status --status-timer 10 \
        --self-test-disable --potfile-disable --backend-ignore-opencl \
        --backend-devices-keepfree=1 \
        --force \
        -D 2 -w 1 > "$LOGFILE" 2>&1 &

    HC_PID=$!

    # 3. Monitor Loop
    final_count=0
    end_time=0

    while true; do
        if ! kill -0 $HC_PID 2>/dev/null; then
            echo "  [WARNING] Hashcat stopped unexpectedly."
            break
        fi

        line=$(grep "Progress" "$LOGFILE" | tail -n 1)

        if [ -n "$line" ]; then
            current=$(echo "$line" | sed -E 's/.*Progress[^:]*: ([0-9]+)\/.*/\1/')
            echo -ne "  [Run $run] Progress: $current / $TARGET ... \r"

            if [ "$current" -ge "$TARGET" ]; then
                echo ""
                kill $HC_PID 2>/dev/null
                wait $HC_PID 2>/dev/null
                final_count=$current
                end_time=$(date +%s.%N)
                break
            fi
        fi
        sleep 5 # Check less frequently to save CPU
    done

    # Fallback timing
    if [ "$end_time" == "0" ]; then end_time=$(date +%s.%N); fi
    if [ "$final_count" -eq 0 ]; then
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

    duration_fmt=$(printf "%.4f" "$duration")
    speed_fmt=$(printf "%.4f" "$speed")

    echo "  -> Result: $speed_fmt H/s ($final_count hashes in ${duration_fmt}s)"
    echo "${run},${MEM_MIB},${TARGET},${final_count},${duration_fmt},${speed_fmt}" >> "$OUT_CSV"

    rm "$HASHFILE" "$LOGFILE"
    echo "  Cooling down for 10s..."
    sleep 10
done

echo "Done. Results in $OUT_CSV"