#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d /tmp/moonrider-package-test.XXXXXX)
if [[ "${KEEP_TEST_TMP:-0}" = 1 ]]; then
  echo "preserving package test: $TMP"
else
  trap 'rm -rf "$TMP"' EXIT
fi

STAGE="$TMP/stage"
OUT="$TMP/Moonrider-PortMaster-BYO.zip"
mkdir -p \
  "$STAGE/moonrider/runtime/bin" \
  "$STAGE/moonrider/runtime/lib/wpe-webkit-1.1" \
  "$STAGE/moonrider/runtime/libs" \
  "$STAGE/moonrider/game"
cp "$ROOT/Moonrider.sh" "$STAGE/Moonrider.sh"
cp "$ROOT/port.json" "$STAGE/port.json"
cp "$ROOT/moonrider/ASSETS-HERE.txt" "$STAGE/moonrider/ASSETS-HERE.txt"
cp "$ROOT/runtime-config/run-moonrider.sh" "$STAGE/moonrider/runtime/run-moonrider.sh"
for rel in \
  bin/moonrider-launch \
  lib/libWPEBackend-mali-fbdev.so \
  libs/libGL.so.1 \
  libs/libWPEWebKit-1.1.so.0 \
  lib/wpe-webkit-1.1/WPEWebProcess; do
  cp "$ROOT/runtime-fixes/libGL.so.1" "$STAGE/moonrider/runtime/$rel"
done
printf 'must not ship\n' > "$STAGE/moonrider/game/c2runtime.js"

STAGING="$STAGE" MOONRIDER_OUT="$OUT" \
  bash "$ROOT/scripts/make-portmaster-zip.sh" >/dev/null
unzip -tq "$OUT" >/dev/null
unzip -Z1 "$OUT" | grep -qx 'moonrider/ASSETS-HERE.txt'
if unzip -Z1 "$OUT" | grep -q '^moonrider/game/.*[^/]$'; then
  echo 'game payload leaked into BYO package' >&2
  exit 1
fi
sha256sum -c "$OUT.sha256" >/dev/null
printf 'test-package: OK\n'
