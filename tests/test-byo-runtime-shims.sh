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
grep -q 'CARD_ROOT=.*SCRIPT_DIR/../..' "$ROOT/Moonrider.sh"
grep -q 'GAMEDIR="\$CARD_ROOT/ports/moonrider"' "$ROOT/Moonrider.sh"
grep -q 'game/index.html' "$ROOT/Moonrider.sh"
grep -q 'game assets missing' "$ROOT/Moonrider.sh"
if grep -q 'GAMEDIR="\$SCRIPT_DIR/moonrider"' "$ROOT/Moonrider.sh"; then
  echo 'launcher must resolve the data directory beside the card-root ports/, not ROMS/Ports/' >&2
  exit 1
fi
if grep -q 'GAMEDIR="/\$directory/' "$ROOT/Moonrider.sh"; then
  echo 'launcher must not hardcode the active ports volume' >&2
  exit 1
fi

# A WebKit/UIProcess deadlock must not hide the only useful log in /run. During
# diagnostics a marker enables an external mirror and the wrapper owns the exact
# child PID so TERM never degenerates into pkill/killall.
grep -q 'LIVE_LOG_MARKER=' "$ROOT/Moonrider.sh"
grep -q 'GAME_PID=\$!' "$ROOT/Moonrider.sh"
grep -q 'LIVE_LOG_PID=\$!' "$ROOT/Moonrider.sh"
grep -q 'kill -TERM "\$GAME_PID"' "$ROOT/Moonrider.sh"
grep -q 'log-live.txt' "$ROOT/Moonrider.sh"
grep -q 'mv -f "\$tmp" "\$PERSIST_LOG"' "$ROOT/Moonrider.sh"
if grep -Eq 'pkill|killall|kill[[:space:]]+-KILL' "$ROOT/Moonrider.sh"; then
  echo 'launcher diagnostics must use exact PIDs and TERM only' >&2
  exit 1
fi
grep -Fq 'kill -TERM "$GAME_PID"' "$ROOT/Moonrider.sh"
grep -Fq 'mv -f "$tmp" "$PERSIST_LOG"' "$ROOT/Moonrider.sh"

# Diagnostic markers must produce a real engine-off A/B, not a mixer-volume mute.
grep -Fq '.audio-disabled' "$ROOT/Moonrider.sh"
grep -Fq 'export MOONRIDER_DISABLE_AUDIO=1' "$ROOT/Moonrider.sh"
grep -Fq '.diagnostics-enabled' "$ROOT/Moonrider.sh"
grep -Fq 'export MUOS_DIAGNOSTICS=1' "$ROOT/Moonrider.sh"
grep -Fq 'export MUOS_FRAME_LOG=1' "$ROOT/Moonrider.sh"
grep -Fq 'MOONRIDER_DISABLE_AUDIO' "$ROOT/native/backend/moonrider-launch.c"
grep -Fq '[audio-ab] engine disabled' "$ROOT/native/backend/moonrider-launch.c"
grep -Fq '[heartbeat] mainloop=' "$ROOT/native/backend/moonrider-launch.c"
if grep -q 'muos_mixer_volume.*0' "$ROOT/native/backend/moonrider-launch.c"; then
  echo 'audio A/B must disable the engine, not mute mixer volume' >&2
  exit 1
fi

printf 'test-byo-runtime-shims: OK\n'
