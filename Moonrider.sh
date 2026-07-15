#!/bin/bash
# PortMaster launcher for Vengeful Guardian: Moonrider
# Runs the Construct 2 / HTML5 build inside a native WPE WebKit runtime (aarch64).
# This is the entry point PortMaster/muOS lists in the Ports menu.

# --- Locate the PortMaster control folder (varies per distro) ------------------
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "/opt/muos/PortMaster/" ]; then
  controlfolder="/opt/muos/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
if [ -z ${TASKSET+x} ]; then
  source $controlfolder/tasksetter
fi

get_controls

# --- Paths ---------------------------------------------------------------------
CUR_TTY=/dev/tty0
PORTDIR="/$directory/ports"
GAMEDIR="$PORTDIR/moonrider"
cd "$GAMEDIR"

$ESUDO chmod 666 $CUR_TTY 2>/dev/null
$ESUDO touch log.txt
$ESUDO chmod 666 log.txt
export TERM=linux
printf "\033c" > $CUR_TTY

# --- Environment for the bundled aarch64 WPE runtime ---------------------------
export LD_LIBRARY_PATH="$GAMEDIR/runtime/libs:$GAMEDIR/libs:$LD_LIBRARY_PATH"
export WEBKIT_INJECTED_BUNDLE_PATH="$GAMEDIR/runtime/lib/wpe-webkit-1.1/injected-bundle"
export WEBKIT_EXEC_PATH="$GAMEDIR/runtime/lib/wpe-webkit-1.1"
export COG_MODULEDIR="$GAMEDIR/runtime/lib/cog/modules"
export GST_PLUGIN_SYSTEM_PATH="$GAMEDIR/runtime/gst-plugins"
export GST_PLUGIN_PATH="$GAMEDIR/runtime/gst-plugins"
export XDG_RUNTIME_DIR="$GAMEDIR/.xdg"
mkdir -p "$XDG_RUNTIME_DIR"

# WPE backend: mali-fbdev is what actually presents on the RG40xx-class hardware.
export WPE_BACKEND_LIBRARY="$GAMEDIR/runtime/lib/libWPEBackend-mali-fbdev.so"
export COG_PLATFORM_NAME=fdo

export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# --- Run -----------------------------------------------------------------------
echo "Starting Moonrider." > $CUR_TTY

$GPTOKEYB "moonrider-launch" &
pm_platform_helper "$GAMEDIR/runtime/bin/cog" 2>/dev/null || true

$TASKSET ./runtime/run-moonrider.sh 2>&1 | $ESUDO tee -a ./log.txt

# --- Cleanup -------------------------------------------------------------------
$ESUDO kill -9 $(pidof gptokeyb) 2>/dev/null
unset LD_LIBRARY_PATH
unset SDL_GAMECONTROLLERCONFIG
$ESUDO systemctl restart oga_events 2>/dev/null &

printf "\033c" > $CUR_TTY
