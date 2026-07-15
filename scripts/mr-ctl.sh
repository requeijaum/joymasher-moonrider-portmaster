#!/bin/sh
# mr-ctl.sh — Moonrider device test controller (muOS / RG40xx H)
#
# Single entry point so the operator authorizes ONE helper instead of many
# ad-hoc destructive commands. The agent edits this script and invokes it.
#
# Subcommands:
#   run [SECONDS]  Stop frontend, launch Moonrider in foreground with full
#                  WebKit/WPE debug, capture EVERYTHING (incl. WPEWebProcess) to
#                  a persistent log on eMMC, then restart the frontend.
#                  Default 15s. Uses setsid so it survives the SSH session.
#   kill           TERM the whole Moonrider chain (never KILL), free fb0,
#                  restart the frontend.
#   status         Show what's running + fb0 render check.
#   log [N]        Print last N lines (default 80) of the last run log,
#                  filtering the per-frame flood.
#   rawlog         Print the full unfiltered log path + tail.
#
# Log lives on eMMC (survives reboot AND the SSH-drop that wipes /run):
#   /mnt/mmc/moonrider-diag.log
set -u

D=/mnt/union/ports/moonrider/runtime
GAMEDIR=/mnt/sdcard/ports/moonrider
LOG=/mnt/mmc/moonrider-diag.log
LOCK=/run/moonrider.lock

mr_env() {
  cd "$D" || exit 1
  export LD_LIBRARY_PATH="$D/libs:$D/lib:/usr/lib/gl4es:/usr/lib:/lib"
  export LIBGL_FB=2 LIBGL_ES=2 WEBKIT_GST_DISABLE_GL_SINK=1
  export GST_PLUGIN_PATH="$D/gst-plugins:$D/libs"
  export GST_PLUGIN_SYSTEM_PATH="$D/gst-plugins:$D/libs"
  export GST_PLUGIN_PATH_1_0="$D/gst-plugins:$D/libs"
  export GST_PLUGIN_SYSTEM_PATH_1_0="$D/gst-plugins:$D/libs"
  export GST_REGISTRY=/run/moonrider/gst-registry.bin
  export GST_REGISTRY_UPDATE=yes GST_REGISTRY_FORK=no
  export XDG_RUNTIME_DIR=/run PIPEWIRE_RUNTIME_DIR=/run
  export XDG_CACHE_HOME=/run/moonrider/.cache
  export WPE_BACKEND="$D/lib/libWPEBackend-mali-fbdev.so"
  export WPE_BACKEND_LIBRARY="$D/lib/libWPEBackend-mali-fbdev.so"
  export WEBKIT_EXEC_PATH="$D/lib/wpe-webkit-1.1"
  export WEBKIT_INJECTED_BUNDLE_PATH="$D/lib/wpe-webkit-1.1/injected-bundle"
  export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
  export WEBKIT_FORCE_COMPOSITING_MODE=1 WEBKIT_FORCE_SANDBOX=0
  export LD_PRELOAD="$D/lib/glx-stub.so"
  export MUOS_DEBUG=1
  # Debug channels — captured to $LOG so we can see the web process spawn/fail.
  export WEBKIT_DEBUG="${WEBKIT_DEBUG:-Process}"
  export G_MESSAGES_DEBUG="${G_MESSAGES_DEBUG:-all}"
  mkdir -p /run/moonrider "$XDG_CACHE_HOME"
  rm -f "$GST_REGISTRY" 2>/dev/null || true
}

frontend_stop() { . /opt/muos/script/var/func.sh 2>/dev/null && FRONTEND stop 2>/dev/null; }
frontend_start() { . /opt/muos/script/var/func.sh 2>/dev/null && FRONTEND start 2>/dev/null; }

mr_kill() {
  for p in moonrider-launch WPEWebProcess WPENetworkProcess run-moonrider Moonrider.sh; do
    pkill -TERM -f "$p" 2>/dev/null && echo "  TERM -> $p"
  done
  sleep 2
  for p in moonrider-launch WPEWebProcess WPENetworkProcess; do
    if pgrep -f "$p" >/dev/null 2>&1; then pkill -TERM -f "$p" 2>/dev/null; echo "  re-TERM -> $p"; fi
  done
  sleep 1
  rm -f "$LOCK"
  pgrep -f moonrider-launch >/dev/null 2>&1 && echo "  WARN: launch still alive" || echo "  launch dead"
}

case "${1:-}" in
  run)
    SECS="${2:-15}"
    echo "== mr-ctl run: ${SECS}s, log=$LOG =="
    mr_kill >/dev/null 2>&1
    : > "$LOG"
    # Write a self-contained runner and launch it fully detached so an SSH
    # disconnect (SIGHUP when frontend stops / pty drops) can't kill it.
    RUNNER=/mnt/mmc/mr-run-inner.sh
    cat > "$RUNNER" <<INNER
#!/bin/sh
. /opt/muos/script/var/func.sh 2>/dev/null && FRONTEND stop 2>/dev/null
sleep 1
cd "$D"
export LD_LIBRARY_PATH="$D/libs:$D/lib:/usr/lib/gl4es:/usr/lib:/lib"
export LIBGL_FB=2 LIBGL_ES=2 WEBKIT_GST_DISABLE_GL_SINK=1
export GST_PLUGIN_PATH="$D/gst-plugins:$D/libs"
export GST_PLUGIN_SYSTEM_PATH="$D/gst-plugins:$D/libs"
export GST_PLUGIN_PATH_1_0="$D/gst-plugins:$D/libs"
export GST_PLUGIN_SYSTEM_PATH_1_0="$D/gst-plugins:$D/libs"
export GST_REGISTRY=/run/moonrider/gst-registry.bin
export GST_REGISTRY_UPDATE=yes GST_REGISTRY_FORK=no
export XDG_RUNTIME_DIR=/run PIPEWIRE_RUNTIME_DIR=/run
export XDG_CACHE_HOME=/run/moonrider/.cache
export WPE_BACKEND="$D/lib/libWPEBackend-mali-fbdev.so"
export WPE_BACKEND_LIBRARY="$D/lib/libWPEBackend-mali-fbdev.so"
export WEBKIT_EXEC_PATH="$D/lib/wpe-webkit-1.1"
export WEBKIT_INJECTED_BUNDLE_PATH="$D/lib/wpe-webkit-1.1/injected-bundle"
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export WEBKIT_FORCE_COMPOSITING_MODE=1 WEBKIT_FORCE_SANDBOX=0
export LD_PRELOAD="$D/lib/glx-stub.so"
export MUOS_DEBUG=1 WEBKIT_DEBUG=Process G_MESSAGES_DEBUG=all
mkdir -p /run/moonrider "\$XDG_CACHE_HOME"
rm -f "\$GST_REGISTRY" 2>/dev/null || true
timeout ${SECS} "$D/bin/moonrider-launch" "file://$GAMEDIR/game/index.html" >> "$LOG" 2>&1
echo "[mr-ctl] exit=\$?" >> "$LOG"
. /opt/muos/script/var/func.sh 2>/dev/null && FRONTEND start 2>/dev/null
INNER
    chmod +x "$RUNNER"
    # nohup + setsid + stdio fully redirected + background = immune to SSH SIGHUP.
    nohup setsid "$RUNNER" </dev/null >/dev/null 2>&1 &
    echo "  launched detached (pid $!); log builds at $LOG"
    echo "  poll with: mr-ctl.sh log   (wait ~$((SECS + 4))s)"
    ;;
  kill)
    echo "== mr-ctl kill =="
    mr_kill
    frontend_start
    ;;
  status)
    echo "== mr-ctl status =="
    pgrep -af moonrider-launch || echo "  moonrider-launch: not running"
    pgrep -af WPEWebProcess || echo "  WPEWebProcess: not running"
    pgrep -af muxfrontend >/dev/null && echo "  frontend: running" || echo "  frontend: NOT running"
    h1=$(md5sum /dev/fb0 2>/dev/null | cut -d' ' -f1)
    sleep 3
    h2=$(md5sum /dev/fb0 2>/dev/null | cut -d' ' -f1)
    [ "$h1" != "$h2" ] && echo "  fb0: CHANGING (rendering)" || echo "  fb0: static"
    ;;
  log)
    N="${2:-80}"
    grep -vE 'frame_will_render|frame_rendered|CHUNK' "$LOG" 2>/dev/null | tail -"$N"
    ;;
  rawlog)
    echo "== $LOG =="
    tail -120 "$LOG" 2>/dev/null
    ;;
  *)
    echo "usage: mr-ctl.sh {run [secs]|kill|status|log [n]|rawlog}"
    ;;
esac
