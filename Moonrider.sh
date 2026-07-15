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

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/moonrider"

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
trap "rm -f $LOCKFILE" EXIT

# --- Stop the muOS frontend to release /dev/fb0 --------------------------------
# NOTE: muOS-specific. On other CFWs this block needs a different teardown.
. /opt/muos/script/var/func.sh
FRONTEND stop

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

# --- Restart the frontend after exit -------------------------------------------
FRONTEND start
cp "$LOGFILE" "$GAMEDIR/log.txt" 2>/dev/null || true
