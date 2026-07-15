#!/bin/sh
set -eu
src=${1:-native/backend/evdev_gamepad.c}
if ! grep -q 'muos_evdev_wait' "$src"; then
    echo 'FAIL: evdev loop does not use muos_evdev_wait' >&2
    exit 1
fi
if grep -q 'usleep(1000)' "$src"; then
    echo 'FAIL: 1ms busy polling remains' >&2
    exit 1
fi
echo 'test-evdev-contract: OK'
