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
GAMEDIR="$SCRIPT_DIR/moonrider"

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
cleanup() {
  [ "$CLEANED" -eq 1 ] && return
  CLEANED=1
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

# --- Run: the WPE runtime launcher points at the game's index.html -------------
./runtime/run-moonrider.sh "file://$GAMEDIR/game/index.html"

# --- Frontend restoration is handled by cleanup() ------------------------------
cp "$LOGFILE" "$GAMEDIR/log.txt" 2>/dev/null || true
