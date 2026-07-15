#!/bin/sh
set -eu

EVDEV=${1:-native/backend/evdev_gamepad.c}
LAUNCH=${2:-native/backend/moonrider-launch.c}
SHIM=${3:-shims/muos_gamepad_shim.js}
BUILD=${4:-scripts/build-launcher-backend.sh}

for token in '[evdev-trace]' '[input-watch] STALL' '[input-watch] RECOVER'; do
    grep -F "$token" "$EVDEV" >/dev/null || { echo "FAIL: missing $token" >&2; exit 1; }
done
for token in '[pad-pulse] GAP' '[pad-pulse] PUSH' '[pad-js] ACK'; do
    grep -F "$token" "$LAUNCH" >/dev/null || { echo "FAIL: missing $token" >&2; exit 1; }
done
for token in 'MUOS_PAD_PUSH' 'MUOS_PAD_READ'; do
    grep -F "$token" "$SHIM" >/dev/null || { echo "FAIL: missing $token" >&2; exit 1; }
done
grep -F 'backend/input_watch.c' "$BUILD" >/dev/null || { echo 'FAIL: input_watch.c absent from launcher build' >&2; exit 1; }

echo 'test-input-stall-instrumentation: OK'
