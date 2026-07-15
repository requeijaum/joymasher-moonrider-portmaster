#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT=/tmp/moonrider-device-benchmark-test.$$
trap 'rm -f "$OUT"' EXIT

"$ROOT/scripts/device-benchmark.sh" "$$" 1 "$OUT"

[ -s "$OUT" ]
for marker in 'MOONRIDER_BENCHMARK_V1' 'PROC_START' 'PROC_END' 'PERF_STATUS' 'CPU_TOPOLOGY'; do
    awk -v marker="$marker" 'index($0, marker) { found=1 } END { exit !found }' "$OUT"
done

echo 'test-device-benchmark: OK'
