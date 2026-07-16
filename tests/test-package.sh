#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d /tmp/moonrider-package-test.XXXXXX)
echo "preserving package test: $TMP"

STAGE="$TMP/stage"
OUT="$TMP/moonrider.zip"
mkdir -p \
  "$STAGE/moonrider/runtime/bin" \
  "$STAGE/moonrider/runtime/lib/wpe-webkit-1.1" \
  "$STAGE/moonrider/runtime/gst-plugins" \
  "$STAGE/moonrider/runtime/LICENSES" \
  "$STAGE/moonrider/runtime/libs" \
  "$STAGE/moonrider/patches" \
  "$STAGE/moonrider/game/media" \
  "$STAGE/moonrider/game"
cp "$ROOT/Moonrider.sh" "$STAGE/Moonrider.sh"
cp "$ROOT/moonrider/port.json" "$STAGE/moonrider/port.json"
cp "$ROOT/moonrider/gameinfo.xml" "$STAGE/moonrider/gameinfo.xml"
cp "$ROOT/moonrider/ASSETS-HERE.txt" "$STAGE/moonrider/ASSETS-HERE.txt"
cp "$ROOT/moonrider/patches/muos_gamepad_shim.js" "$STAGE/moonrider/patches/"
cp "$ROOT/moonrider/patches/muos_audio_ghost.js" "$STAGE/moonrider/patches/"
cp "$ROOT/runtime-config/run-moonrider.sh" "$STAGE/moonrider/runtime/run-moonrider.sh"
for rel in \
  bin/moonrider-launch \
  lib/libWPEBackend-mali-fbdev.so \
  lib/glx-stub.so \
  libs/libGL.so.1 \
  libs/libWPEWebKit-1.1.so.0 \
  lib/wpe-webkit-1.1/WPEWebProcess \
  gst-plugins/libgstcoreelements.so \
  gst-plugins/libgstcoretracers.so; do
  cp "$ROOT/runtime-fixes/libGL.so.1" "$STAGE/moonrider/runtime/$rel"
done
for n in $(seq -w 1 22); do
  cp "$ROOT/runtime-fixes/libGL.so.1" \
    "$STAGE/moonrider/runtime/gst-plugins/libgstsynthetic$n.so"
done
printf '\0MOONRIDER_SHIM_DIR\0muos_gamepad_shim.js\0muos_audio_ghost.js\0' \
  >> "$STAGE/moonrider/runtime/bin/moonrider-launch"
printf 'Synthetic test-only provenance; not releasable.\n' > \
  "$STAGE/moonrider/runtime/RUNTIME-PROVENANCE.md"
printf 'Synthetic test-only license payload.\n' > \
  "$STAGE/moonrider/runtime/LICENSES/TEST-ONLY.txt"
python3 "$ROOT/scripts/generate-runtime-manifest.py" \
  "$STAGE/moonrider/runtime" >/dev/null
printf 'must not ship\n' > "$STAGE/moonrider/game/c2runtime.js"
printf 'nested asset must not ship\n' > "$STAGE/moonrider/game/media/private.ogg"

STAGING="$STAGE" MOONRIDER_OUT="$OUT" \
  bash "$ROOT/scripts/make-portmaster-zip.sh" >/dev/null
unzip -tq "$OUT" >/dev/null
unzip -Z1 "$OUT" | grep -qx 'moonrider/ASSETS-HERE.txt'
unzip -Z1 "$OUT" | grep -qx 'moonrider/port.json'
unzip -Z1 "$OUT" | grep -qx 'moonrider/gameinfo.xml'
if unzip -Z1 "$OUT" | grep -qx 'port.json'; then
  echo 'PortMaster v4 metadata leaked to ZIP root' >&2
  exit 1
fi
unzip -Z1 "$OUT" | grep -qx 'moonrider/patches/muos_gamepad_shim.js'
unzip -Z1 "$OUT" | grep -qx 'moonrider/patches/muos_audio_ghost.js'
python3 - "$OUT" <<'PY'
import json, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as zf:
    metadata = json.loads(zf.read('moonrider/port.json'))
    assert metadata['version'] == 4
    assert metadata['name'] == 'moonrider.zip'
    assert metadata['items'] == ['Moonrider.sh', 'moonrider']
    assert metadata['items_opt'] is None
    assert metadata['attr']['runtime'] == []
    assert metadata['attr']['reqs'] == []
    assert metadata['attr']['arch'] == ['aarch64']
    for name in ('Moonrider.sh', 'moonrider/runtime/run-moonrider.sh'):
        mode = (zf.getinfo(name).external_attr >> 16) & 0o777
        assert mode == 0o755, f'{name}: expected 0755, got {mode:04o}'
PY
if unzip -Z1 "$OUT" | grep -q '^moonrider/game/.*[^/]$'; then
  echo 'game payload leaked into BYO package' >&2
  exit 1
fi
(
  cd "$TMP"
  sha256sum -c "$(basename "$OUT").sha256" >/dev/null
)
grep -q '  moonrider/patches/muos_audio_ghost.js$' "$OUT.manifest.sha256"
if grep -q '  moonrider/game/' "$OUT.manifest.sha256"; then
  echo 'game payload leaked into per-file manifest' >&2
  exit 1
fi

# Commercial payloads are forbidden anywhere outside the excluded game/ tree.
LEAK_STAGE="$TMP/leak-stage"
cp -a "$STAGE" "$LEAK_STAGE"
printf 'commercial payload\n' > "$LEAK_STAGE/moonrider/runtime/data.js"
python3 "$ROOT/scripts/generate-runtime-manifest.py" \
  "$LEAK_STAGE/moonrider/runtime" >/dev/null
if STAGING="$LEAK_STAGE" MOONRIDER_OUT="$TMP/leak.zip" \
  bash "$ROOT/scripts/make-portmaster-zip.sh" >/dev/null 2>&1; then
  echo 'packager accepted commercial payload outside game/' >&2
  exit 1
fi

# Same staging must produce the same ZIP bytes regardless of caller timezone.
OUT_TZ="$TMP/moonrider-timezone-check.zip"
TZ=Pacific/Kiritimati STAGING="$STAGE" MOONRIDER_OUT="$OUT_TZ" \
  bash "$ROOT/scripts/make-portmaster-zip.sh" >/dev/null
cmp -s "$OUT" "$OUT_TZ" || {
  echo 'package is not byte-reproducible across caller timezones' >&2
  exit 1
}

# Release builder must not overwrite an existing artifact.
if STAGING="$STAGE" MOONRIDER_OUT="$OUT" \
  bash "$ROOT/scripts/make-portmaster-zip.sh" >/dev/null 2>&1; then
  echo 'packager overwrote an existing artifact' >&2
  exit 1
fi
printf 'test-package: OK\n'
