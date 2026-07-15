#!/bin/sh
# device-benchmark.sh — bounded benchmark collector for Moonrider/WPE processes.
# Usage: device-benchmark.sh PID [SECONDS] [OUTPUT]
set -u

PID=${1:-}
DURATION=${2:-60}
OUT=${3:-/tmp/moonrider-benchmark-${PID:-unknown}.txt}

case "$PID" in ''|*[!0-9]*) echo "usage: $0 PID [SECONDS] [OUTPUT]" >&2; exit 2;; esac
case "$DURATION" in ''|*[!0-9]*) echo "SECONDS must be an integer" >&2; exit 2;; esac
[ "$DURATION" -gt 0 ] || { echo "SECONDS must be > 0" >&2; exit 2; }
[ -d "/proc/$PID" ] || { echo "PID $PID not found" >&2; exit 3; }

mkdir -p "$(dirname "$OUT")" || exit 4

read_file() {
    label=$1
    path=$2
    echo "--- $label $path"
    if [ -r "$path" ]; then
        while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line"; done < "$path"
    else
        echo "UNAVAILABLE"
    fi
}

proc_snapshot() {
    phase=$1
    echo "=== PROC_$phase"
    read_file STAT "/proc/$PID/stat"
    echo "--- STATUS_SELECTED"
    if [ -r "/proc/$PID/status" ]; then
        awk '/^(Name|Pid|Threads|VmPeak|VmSize|VmRSS|VmHWM|RssAnon|RssFile|voluntary_ctxt_switches|nonvoluntary_ctxt_switches):/' "/proc/$PID/status"
    else
        echo "UNAVAILABLE"
    fi
    echo "--- SCHED_SELECTED"
    if [ -r "/proc/$PID/sched" ]; then
        awk '/^(se.sum_exec_runtime|nr_switches|nr_voluntary_switches|nr_involuntary_switches|se.nr_migrations)/' "/proc/$PID/sched"
    else
        echo "UNAVAILABLE"
    fi
    echo "--- SMAPS_ROLLUP_SELECTED"
    if [ -r "/proc/$PID/smaps_rollup" ]; then
        awk '/^(Rss|Pss|Private_Clean|Private_Dirty|Shared_Clean|Shared_Dirty):/' "/proc/$PID/smaps_rollup"
    else
        echo "UNAVAILABLE"
    fi
}

{
    echo "MOONRIDER_BENCHMARK_V1"
    echo "PID=$PID"
    echo "DURATION_SECONDS=$DURATION"
    echo "START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
    echo "KERNEL=$(uname -srmo 2>/dev/null || uname -a)"

    echo "=== CPU_TOPOLOGY"
    read_file CPU_ONLINE /sys/devices/system/cpu/online
    for path in /sys/devices/system/cpu/cpu0/cache/index*/level \
                /sys/devices/system/cpu/cpu0/cache/index*/type \
                /sys/devices/system/cpu/cpu0/cache/index*/size \
                /sys/devices/system/cpu/cpu0/cache/index*/coherency_line_size; do
        [ -e "$path" ] && read_file CACHE "$path"
    done
    for path in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
        [ -e "$path" ] && read_file CPU_FREQ "$path"
    done
    for path in /sys/class/thermal/thermal_zone*/temp; do
        [ -e "$path" ] && read_file THERMAL "$path"
    done

    proc_snapshot START

    echo "=== PERF_STATUS"
    if command -v perf >/dev/null 2>&1; then
        echo "AVAILABLE=$(command -v perf)"
        echo "--- PERF_STAT"
        perf stat -x ';' \
            -e task-clock,context-switches,cpu-migrations,page-faults,cycles,instructions,branches,branch-misses,cache-references,cache-misses \
            -p "$PID" -- sleep "$DURATION" 2>&1
        PERF_RC=$?
        echo "PERF_RC=$PERF_RC"
        if [ "$PERF_RC" -ne 0 ]; then
            echo "PERF_FAILED_FALLBACK_SLEEP=1"
            sleep "$DURATION"
        fi
    else
        echo "AVAILABLE=0"
        sleep "$DURATION"
    fi

    proc_snapshot END
    for path in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
        [ -e "$path" ] && read_file CPU_FREQ_END "$path"
    done
    for path in /sys/class/thermal/thermal_zone*/temp; do
        [ -e "$path" ] && read_file THERMAL_END "$path"
    done
    echo "END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
} > "$OUT" 2>&1

printf '%s\n' "$OUT"
