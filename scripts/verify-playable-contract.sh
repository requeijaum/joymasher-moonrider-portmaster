#!/bin/bash
# Source/package regression gate. Device playability remains a separate smoke test.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT_ROOT="${1:-}"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

# Tracked source/config contract.
for f in \
  "$ROOT/runtime-fixes/libgl-stub.c" \
  "$ROOT/runtime-fixes/libGL.so.1" \
  "$ROOT/native/backend/moonrider-launch.c" \
  "$ROOT/native/audio-mixer/muos_audio_mixer.c" \
  "$ROOT/moonrider/patches/muos_audio_ghost.js" \
  "$ROOT/moonrider/patches/muos_gamepad_shim.js" \
  "$ROOT/runtime-config/run-moonrider.sh"; do
  [[ -f "$f" ]] || fail "required source absent: ${f#$ROOT/}"
done
ok "canonical sources present"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import hashlib, json, sys
root = Path(sys.argv[1])
manifest = json.loads((root / "manifests/PLAYABLE-V2.json").read_text())
for rel, expected in manifest["canonical_sources_md5"].items():
    actual = hashlib.md5((root / rel).read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit(f"FAIL: source hash drift: {rel}: {actual} != {expected}")
print("OK: canonical source hashes match PLAYABLE-V2 manifest")
PY

grep -q 'strcmp(cmd, "PLAYPAIR")' "$ROOT/native/backend/moonrider-launch.c" || fail "launcher source lacks PLAYPAIR parser"
grep -q 'muos_mixer_play_pair' "$ROOT/native/audio-mixer/muos_audio_mixer.c" || fail "mixer source lacks PLAYPAIR scheduler"
grep -q 'PLAYPAIR|' "$ROOT/moonrider/patches/muos_audio_ghost.js" || fail "ghost lacks PLAYPAIR emitter"
grep -q 'AP.cnds.IsTagPlaying = function' "$ROOT/moonrider/patches/muos_audio_ghost.js" || fail "ghost lacks native IsTagPlaying bridge"
node "$ROOT/tests/test-audio-ghost.js" >/dev/null || fail "audio ghost behavior test failed"
ok "coupled PLAYPAIR trio and native IsTagPlaying bridge present"

for var in GST_PLUGIN_PATH GST_PLUGIN_SYSTEM_PATH GST_PLUGIN_PATH_1_0 GST_PLUGIN_SYSTEM_PATH_1_0; do
  grep -q "export $var=\"\$HERE/gst-plugins\"" "$ROOT/runtime-config/run-moonrider.sh" || fail "$var is not restricted to gst-plugins"
done
if grep -q 'gst-plugins:.*libs' "$ROOT/runtime-config/run-moonrider.sh"; then
  fail "runtime config scans libs/ as GStreamer plugins"
fi
grep -q 'WEBKIT_EXEC_PATH=' "$ROOT/runtime-config/run-moonrider.sh" || fail "WEBKIT_EXEC_PATH missing"
grep -q 'SAFE_QUIT=/run/muos_safe_quit' "$ROOT/Moonrider.sh" || fail "SAFE_QUIT frontend teardown missing"
ok "runtime/frontend configuration contract"

file "$ROOT/runtime-fixes/libGL.so.1" | grep -q 'ARM aarch64' || fail "tracked libGL stub is not aarch64 ELF"
grep -q 'glXGetCurrentContext' "$ROOT/runtime-fixes/libgl-stub.c" || fail "stub source lacks glXGetCurrentContext"
ok "libGL EGL-forcing stub contract"

# BYO assets remain byte-identical; runtime shims are injected by the launcher.
bash "$ROOT/tests/test-extract-assets.sh" >/dev/null || fail "raw BYO extraction contract failed"
bash "$ROOT/tests/test-byo-runtime-shims.sh" >/dev/null || fail "runtime shim injection contract failed"
ok "raw BYO extraction and runtime injection contract"

# Optional assembled staging contract.
if [[ -n "$PORT_ROOT" ]]; then
  R="$PORT_ROOT/runtime"
  G="$PORT_ROOT/game"
  P="$PORT_ROOT/patches"
  [[ -f "$R/libs/libGL.so.1" ]] || fail "staging runtime lacks libs/libGL.so.1"
  [[ -f "$R/bin/moonrider-launch" ]] || fail "staging runtime lacks launcher"
  grep -qa PLAYPAIR "$R/bin/moonrider-launch" || fail "staging launcher lacks PLAYPAIR"
  grep -qa MOONRIDER_SHIM_DIR "$R/bin/moonrider-launch" || fail "staging launcher lacks runtime shim injection"
  [[ -f "$P/muos_audio_ghost.js" ]] || fail "staging port lacks audio ghost"
  [[ -f "$P/muos_gamepad_shim.js" ]] || fail "staging port lacks gamepad shim"
  grep -q 'PLAYPAIR|' "$P/muos_audio_ghost.js" || fail "staging ghost lacks PLAYPAIR"
  python3 - "$ROOT" "$PORT_ROOT" <<'PY'
from pathlib import Path
import hashlib, sys
root, port = map(Path, sys.argv[1:])
game = port / "game"
if game.exists() and any(path.is_file() for path in game.rglob("*")):
    raise SystemExit("FAIL: asset-free BYO staging contains commercial game files")
for name in ("muos_audio_ghost.js", "muos_gamepad_shim.js"):
    src = root / "moonrider/patches" / name
    packaged = port / "patches" / name
    if hashlib.sha256(src.read_bytes()).digest() != hashlib.sha256(packaged.read_bytes()).digest():
        raise SystemExit(f"FAIL: packaged patch drift: {name}")
print("OK: asset-free BYO staging uses canonical runtime patches")
PY
  ok "assembled BYO staging satisfies the current port contract"
fi

echo "PASS: Moonrider source/BYO contract (device smoke test still required)"
