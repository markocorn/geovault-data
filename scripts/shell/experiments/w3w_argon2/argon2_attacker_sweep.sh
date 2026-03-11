#!/usr/bin/env bash
# argon2_attacker_sweep_v9_perfect.sh
# Benchmarking GPU Argon2id on RTX A6000
# FIX: Regex adjusted to match any number of dots in "Progress" line.

set -u

# ──────────────── Configuration ─────────────────────
RUNS=100
BASE_RUNTIME=600
ARGON2_MODE="34000"

T_COST="${T_COST:-1}"
P_LANES="${P_LANES:-1}"

MEM_MIB_LIST="8192"

#MEM_MIB_LIST="2048 4096 8192"

#MEM_MIB_LIST="64 128 256 512 1024"

# ──────────────── Functions ─────────────────────────

parse_speed_robust() {
    local out="$1"
    local runtime="$2"

    # 1. Grab Speed for Fast Tiers (> 100 H/s)
    local speed_line
    speed_line=$(echo "$out" | grep "Speed\.#" | tail -n 1)

    local speed_val
    speed_val=$(echo "$speed_line" | awk '{print $2}')
    local unit
    unit=$(echo "$speed_line" | awk '{print $3}')

    if [ "$unit" == "kH/s" ]; then
        speed_val=$(awk -v v="$speed_val" 'BEGIN {print v * 1000}')
    elif [ "$unit" == "MH/s" ]; then
        speed_val=$(awk -v v="$speed_val" 'BEGIN {print v * 1000000}')
    fi

    # Logic: If speed is >100, use Hashcat's number. If <100, calculate manually for precision.
    if [ -n "$speed_val" ] && [ $(awk -v v="$speed_val" 'BEGIN {print (v > 100 ? 1 : 0)}') -eq 1 ]; then
        echo "$speed_val"
        return
    fi

    # 2. Precise Calculation for Slow Tiers (4GB/8GB)
    # REGEX FIX: Match "Progress" followed by ANY dots or spaces, then a colon
    local hashes_done
    hashes_done=$(echo "$out" | grep "Progress.*:" | tail -n 1 | awk '{print $2}' | cut -d'/' -f1)

    if [ -z "$hashes_done" ]; then
        echo "FAIL"
        return
    fi

    # Math: Progress / Runtime
    awk -v done="$hashes_done" -v time="$runtime" 'BEGIN {
        if (time == 0) print "0.0000";
        else printf "%.4f", done / time;
    }'
}

# ──────────────── Main Execution ────────────────────
echo "=== Hashcat GPU Sweep: Argon2id (Final Fix) ==="
echo "Hardware: NVIDIA RTX A6000"
echo "Mask:     ?b?b?b?b?b?b?b (7-byte binary brute force)"

for mem in $MEM_MIB_LIST; do
    echo "------------------------------------------------"
    echo ">>> Testing Memory: ${mem} MiB"
    MEM_KIB=$((mem * 1024))

    # Dynamic Runtime for high memory
    CURRENT_RUNTIME=$BASE_RUNTIME
#    [ "$mem" -ge 2048 ] && CURRENT_RUNTIME=60
#    [ "$mem" -ge 4096 ] && CURRENT_RUNTIME=120
#    [ "$mem" -ge 8192 ] && CURRENT_RUNTIME=180

    OUT_CSV="argon2_gpu_m${mem}MiB.csv"
    echo "Run,Mem_MiB,T_cost,Lanes,HashRate_Hs" > "$OUT_CSV"

    HASHFILE=$(mktemp --suffix=.hash)

    # Valid Hash Generation
    python3 -c "
import base64
m = $MEM_KIB
t = $T_COST
p = $P_LANES
salt = base64.b64encode(b'1234567890123456').decode('utf-8').replace('=', '')
tag = base64.b64encode(b'\x00' * 32).decode('utf-8').replace('=', '')
print(f'\$argon2id\$v=19\$m={m},t={t},p={p}\${salt}\${tag}')
" > "$HASHFILE"

    for run in $(seq 1 "$RUNS"); do
        echo -n "  run $run/$RUNS (t=${CURRENT_RUNTIME}s)... "

        WORKLOAD=3
        [ "$mem" -ge 4096 ] && WORKLOAD=1

        # Use -w 1 for 4GB+ to prevent screen freeze/driver timeout
        HC_OUT=$(hashcat -m "$ARGON2_MODE" "$HASHFILE" -a 3 ?b?b?b?b?b?b?b \
                 --runtime "$CURRENT_RUNTIME" \
                 --status --status-timer 1 \
                 --self-test-disable \
                 --potfile-disable \
                 --backend-ignore-opencl \
                 -D 2 \
                 -w "$WORKLOAD" 2>&1)

        HASHRATE=$(parse_speed_robust "$HC_OUT" "$CURRENT_RUNTIME")

        if [ "$HASHRATE" == "FAIL" ] || [ -z "$HASHRATE" ]; then
            echo "[FAILED]"
            if echo "$HC_OUT" | grep -q "Out of Device Memory"; then
                 echo "    [CRITICAL] Out of VRAM. Stopping."
                 break
            fi
            # Debug output if it still fails
            echo "$HC_OUT" | grep "Progress" | tail -n 1
            continue
        fi

        echo "${HASHRATE} H/s"
        echo "${run},${mem},${T_COST},${P_LANES},${HASHRATE}" >> "$OUT_CSV"
    done

    rm -f "$HASHFILE"
    echo "  Saved -> $OUT_CSV"
done

echo "------------------------------------------------"
echo "Done."