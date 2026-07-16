#!/bin/bash
# PORTMASTER: Moonrider.zip, Moonrider.sh
# PortMaster launcher for Vengeful Guardian: Moonrider.
# Serves the Construct 2 / HTML5 build through a bundled aarch64 WPE WebKit
# runtime (moonrider-launch + libWPEBackend-mali-fbdev), rendering to /dev/fb0.
#
# Tested ONLY on Anbernic RG40xx H / muOS 2508.4 "LOOSE GOOSE".

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

# --- Locate the PortMaster control folder (varies per distro) ------------------
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source "$controlfolder/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CARD_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
GAMEDIR="$CARD_ROOT/ports/moonrider"

# Fail before stopping the frontend when the PortMaster data directory or the
# user-supplied game export is absent. Keep this diagnostic on the card because
# /run is not reachable through muOS's restricted SFTP service.
if [ ! -d "$GAMEDIR/runtime" ]; then
  printf '[moonrider-wpe] ERROR: installed runtime not found at %s/runtime\n' "$GAMEDIR" \
    > "$SCRIPT_DIR/Moonrider.log"
  exit 2
fi
if [ ! -s "$GAMEDIR/game/index.html" ]; then
  printf '[moonrider-wpe] ERROR: game assets missing; copy a legitimate export into %s/game/\n' "$GAMEDIR" \
    > "$GAMEDIR/log.txt"
  exit 2
fi

# --- Single-instance lock ------------------------------------------------------
LOCKFILE="/run/moonrider.lock"
if [ -e "$LOCKFILE" ]; then
  PID=$(cat "$LOCKFILE" 2>/dev/null || echo "")
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    echo "Moonrider já está rodando (PID $PID). Ignorando."
    exit 0
  fi
fi
echo $$ > "$LOCKFILE"

SAFE_QUIT=/run/muos_safe_quit
FRONTEND_FROZEN=""
CLEANED=0
GAME_PID=""
LIVE_LOG_PID=""
LOGFILE=""
PERSIST_LOG="$GAMEDIR/log-live.txt"
LIVE_LOG_MARKER="$GAMEDIR/.live-log-enabled"

persist_log() {
  [ -n "$LOGFILE" ] && [ -f "$LOGFILE" ] || return 0
  local tmp="$PERSIST_LOG.tmp.${BASHPID:-$$}"
  cp "$LOGFILE" "$tmp" 2>/dev/null && mv -f "$tmp" "$PERSIST_LOG"
}

mirror_live_log() {
  trap 'exit 0' INT TERM
  while [ -n "$GAME_PID" ] && kill -0 "$GAME_PID" 2>/dev/null; do
    sleep 2
    persist_log
  done
  persist_log
}

cleanup() {
  [ "$CLEANED" -eq 1 ] && return
  CLEANED=1
  if [ -n "$GAME_PID" ] && kill -0 "$GAME_PID" 2>/dev/null; then
    kill -TERM "$GAME_PID" 2>/dev/null || true
    wait "$GAME_PID" 2>/dev/null || true
  fi
  if [ -n "$LIVE_LOG_PID" ] && kill -0 "$LIVE_LOG_PID" 2>/dev/null; then
    kill -TERM "$LIVE_LOG_PID" 2>/dev/null || true
    wait "$LIVE_LOG_PID" 2>/dev/null || true
  fi
  persist_log
  [ -n "$LOGFILE" ] && cp "$LOGFILE" "$GAMEDIR/log.txt" 2>/dev/null || true
  rm -f "$LOCKFILE" "$SAFE_QUIT"
  if [ -n "$FRONTEND_FROZEN" ]; then
    FPID=$(pgrep -x muxfrontend 2>/dev/null || true)
    [ -n "$FPID" ] && kill -CONT "$FPID" 2>/dev/null || true
  else
    FRONTEND start 2>/dev/null || true
  fi
}
on_signal() { exit 130; }
trap cleanup EXIT
trap on_signal INT TERM

# --- Stop the muOS frontend to release /dev/fb0 --------------------------------
# FRONTEND stop only exits muxfrontend when SAFE_QUIT is exported and its flag
# exists. SSH/PortMaster wrappers do not reliably inherit that variable.
. /opt/muos/script/var/func.sh
export SAFE_QUIT
: > "$SAFE_QUIT"
FRONTEND stop
sleep 1
if pgrep -x muxfrontend >/dev/null 2>&1; then
  kill -STOP "$(pgrep -x muxfrontend)" 2>/dev/null && FRONTEND_FROZEN=1
fi

# --- Logging to tmpfs (avoid SD/eMMC wear) -------------------------------------
mkdir -p /run/moonrider
LOGFILE="/run/moonrider/log.txt"
: > "$LOGFILE"
exec > >(tee "$LOGFILE") 2>&1

echo "[moonrider-wpe] $(date)"
echo "[moonrider-wpe] GAMEDIR=$GAMEDIR"
echo "[moonrider-wpe] launching WPE..."

cd "$GAMEDIR"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

if [ -e "$GAMEDIR/.audio-disabled" ]; then
  export MOONRIDER_DISABLE_AUDIO=1
  echo "[moonrider-wpe] audio A/B: native engine disabled"
fi
if [ -e "$GAMEDIR/.diagnostics-enabled" ]; then
  export MUOS_DIAGNOSTICS=1
  export MUOS_FRAME_LOG=1
  echo "[moonrider-wpe] diagnostics enabled: mainloop heartbeat + frame counters"
fi

# --- Run: retain the exact child PID for safe TERM and independent diagnostics. -
./runtime/run-moonrider.sh "file://$GAMEDIR/game/index.html" &
GAME_PID=$!
if [ -e "$LIVE_LOG_MARKER" ]; then
  echo "[moonrider-wpe] live log mirror enabled: $PERSIST_LOG"
  mirror_live_log &
  LIVE_LOG_PID=$!
fi

wait "$GAME_PID"
GAME_STATUS=$?
GAME_PID=""

if [ -n "$LIVE_LOG_PID" ] && kill -0 "$LIVE_LOG_PID" 2>/dev/null; then
  kill -TERM "$LIVE_LOG_PID" 2>/dev/null || true
  wait "$LIVE_LOG_PID" 2>/dev/null || true
fi
LIVE_LOG_PID=""

# --- Frontend restoration is handled by cleanup() ------------------------------
persist_log
cp "$LOGFILE" "$GAMEDIR/log.txt" 2>/dev/null || true
exit "$GAME_STATUS"
