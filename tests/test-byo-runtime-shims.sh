#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for shim in muos_gamepad_shim.js muos_audio_ghost.js; do
  test -s "$ROOT/moonrider/patches/$shim"
done

# Assets are copied after installation, so the WPE launcher itself must inject
# the compatibility layer before the game's c2runtime.js executes.
grep -q 'MOONRIDER_SHIM_DIR' "$ROOT/runtime-config/run-moonrider.sh"
grep -q 'webkit_user_content_manager_add_script' \
  "$ROOT/native/backend/moonrider-launch.c"
grep -q 'WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START' \
  "$ROOT/native/backend/moonrider-launch.c"
grep -q 'muos_gamepad_shim.js' "$ROOT/native/backend/moonrider-launch.c"
grep -q 'muos_audio_ghost.js' "$ROOT/native/backend/moonrider-launch.c"
python3 - "$ROOT/native/backend/moonrider-launch.c" <<'PY'
import sys
source = open(sys.argv[1], encoding='utf-8').read()
audio = source.index('add_user_script_file(ucm, audio_shim)')
gamepad = source.index('add_user_script_file(ucm, gamepad_shim)')
assert audio < gamepad, 'PLAYABLE-V2 order requires Audio Ghost before gamepad'
PY
if grep -q '^export MUOS_DEBUG=1$' "$ROOT/runtime-config/run-moonrider.sh"; then
  echo 'release runtime must not force verbose JS console logging' >&2
  exit 1
fi

grep -q 'SCRIPT_DIR=.*BASH_SOURCE' "$ROOT/Moonrider.sh"
grep -q 'GAMEDIR="\$SCRIPT_DIR/moonrider"' "$ROOT/Moonrider.sh"
if grep -q 'GAMEDIR="/\$directory/' "$ROOT/Moonrider.sh"; then
  echo 'launcher must not hardcode the active ports volume' >&2
  exit 1
fi

printf 'test-byo-runtime-shims: OK\n'
