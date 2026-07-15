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
#   run42 [SECONDS] Same controlled run using the isolated WPE 2.42 engine
#                  overlay at /mnt/mmc/moonrider-wpe-2.42.
#   kill           TERM the whole Moonrider chain (never KILL), free fb0,
#                  restart the frontend.
#   status         Show what's running + fb0 render check.
#   log [N]        Print last N lines (default 80) of the last run log,
#                  filtering the per-frame flood.
#   log42 [N]      Print the filtered WPE 2.42 pilot log.
#   rawlog         Print the full unfiltered log path + tail.
#   rawlog42       Print the unfiltered WPE 2.42 pilot log tail.
#
# Log lives on eMMC (survives reboot AND the SSH-drop that wipes /run):
#   /mnt/mmc/moonrider-diag.log
set -u

D=/mnt/union/ports/moonrider/runtime
GAMEDIR=/mnt/sdcard/ports/moonrider
LOG=/mnt/mmc/moonrider-diag.log
LOG42=/mnt/mmc/moonrider-diag-2.42.log
LOCK=/run/moonrider.lock

# BusyBox pgrep may not match executable paths reliably. Inspect argv[0] and
# compare its basename exactly; this never matches the controller's own shell.
proc_pids() {
  WANT="$1"
  for DPID in /proc/[0-9]*; do
    [ -r "$DPID/cmdline" ] || continue
    ARG0=$(tr '\000' '\n' < "$DPID/cmdline" 2>/dev/null | sed -n '1p')
    [ "${ARG0##*/}" = "$WANT" ] && echo "${DPID##*/}"
  done
}

mr_env() {
  cd "$D" || exit 1
  export LD_LIBRARY_PATH="$D/libs:$D/lib:/usr/lib/gl4es:/usr/lib:/lib"
  export LIBGL_FB=2 LIBGL_ES=2 WEBKIT_GST_DISABLE_GL_SINK=1
  export GST_PLUGIN_PATH="$D/gst-plugins"
  export GST_PLUGIN_SYSTEM_PATH="$D/gst-plugins"
  export GST_PLUGIN_PATH_1_0="$D/gst-plugins"
  export GST_PLUGIN_SYSTEM_PATH_1_0="$D/gst-plugins"
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

frontend_start() { . /opt/muos/script/var/func.sh 2>/dev/null && FRONTEND start launcher 2>/dev/null; }

mr_kill() {
  # Match executable names only. Never broad-match command lines or the SSH/controller.
  PIDS=""
  for p in moonrider-launch WPEWebProcess WPENetworkProcess; do
    for pid in $(proc_pids "$p"); do
      case " $PIDS " in *" $pid "*) ;; *) PIDS="$PIDS $pid";; esac
    done
  done
  if [ -n "$PIDS" ]; then
    for pid in $PIDS; do kill -TERM "$pid" 2>/dev/null && echo "  TERM -> $pid"; done
    sleep 2
  fi
  rm -f "$LOCK"
  [ -n "$(proc_pids moonrider-launch)" ] && echo "  WARN: launch still alive" || echo "  launch dead"
}

case "${1:-}" in
  run|run42)
    SECS="${2:-15}"
    ENGINE="$D"
    VARIANT=2.38
    RUNLOG="$LOG"
    RUNNER=/mnt/mmc/mr-run-inner.sh
    LOGCMD=log
    if [ "$1" = run42 ]; then
      ENGINE=/mnt/mmc/moonrider-wpe-2.42
      VARIANT=2.42
      RUNLOG="$LOG42"
      RUNNER=/mnt/mmc/mr-run-inner-2.42.sh
      LOGCMD=log42
      [ -f "$ENGINE/libs/libWPEWebKit-1.1.so.0" ] || {
        echo "missing WPE 2.42 overlay: $ENGINE" >&2
        exit 1
      }
    fi
    echo "== mr-ctl run: WPE ${VARIANT}, ${SECS}s, log=$RUNLOG =="
    mr_kill >/dev/null 2>&1
    : > "$RUNLOG"
    # Write a self-contained runner and launch it fully detached so an SSH
    # disconnect (SIGHUP when frontend stops / pty drops) can't kill it.
    cat > "$RUNNER" <<INNER
#!/bin/sh
# --- robust frontend teardown: USR1 -> TERM -> STOP, never KILL -----------
. /opt/muos/script/var/func.sh 2>/dev/null || exit 1
SAFE_QUIT=/tmp/safe_quit
export SAFE_QUIT
FRONTEND_LD_LIBRARY_PATH="\$LD_LIBRARY_PATH"
: > "\$SAFE_QUIT" 2>/dev/null || true
SIGNAL_FRONTEND USR1
I=5
while FRONTEND_RUNNING && [ "\$I" -gt 0 ]; do
  sleep 1
  I=\$((I - 1))
done
if FRONTEND_RUNNING; then
  SIGNAL_FRONTEND TERM
  I=3
  while FRONTEND_RUNNING && [ "\$I" -gt 0 ]; do
    sleep 1
    I=\$((I - 1))
  done
fi
FROZEN_PIDS=""
if FRONTEND_RUNNING; then
  FROZEN_PIDS="\$(GET_FRONTEND_PIDS)"
  for PID in \$FROZEN_PIDS; do kill -STOP "\$PID" 2>/dev/null || true; done
fi
sleep 1
cd "$D"
export LD_LIBRARY_PATH="$ENGINE/libs:$D/libs:$D/lib:/usr/lib/gl4es:/usr/lib:/lib"
# CRITICO (fix 20260715): $D/libs contem uma libGL.so.1 STUB propria que precede
# /usr/lib/gl4es no path. O libepoxy tem NEEDED libGL.so.1; se resolver o gl4es real
# (que NAO exporta glXGetCurrentContext) o WebProcess ABORTA a init GL antes do 1o
# frame ("glXGetCurrentContext() not found"). Com a stub (todos glX -> NULL) o epoxy
# cai no path EGL e o jogo renderiza. Fonte: runtime-fixes/libgl-stub.c
export LIBGL_FB=2 LIBGL_ES=2 WEBKIT_GST_DISABLE_GL_SINK=1
# GST_PLUGIN_PATH so gst-plugins (NAO incluir libs: evita o scanner tentar carregar
# libgstgl-1.0.so como plugin, que falha em glXMakeCurrent).
export GST_PLUGIN_PATH="$D/gst-plugins"
export GST_PLUGIN_SYSTEM_PATH="$D/gst-plugins"
export GST_PLUGIN_PATH_1_0="$D/gst-plugins"
export GST_PLUGIN_SYSTEM_PATH_1_0="$D/gst-plugins"
export GST_REGISTRY=/run/moonrider/gst-registry.bin
export GST_REGISTRY_UPDATE=yes GST_REGISTRY_FORK=no
export XDG_RUNTIME_DIR=/run PIPEWIRE_RUNTIME_DIR=/run
export XDG_CACHE_HOME=/run/moonrider/.cache
export WPE_BACKEND="$D/lib/libWPEBackend-mali-fbdev.so"
export WPE_BACKEND_LIBRARY="$D/lib/libWPEBackend-mali-fbdev.so"
export WEBKIT_EXEC_PATH="$ENGINE/lib/wpe-webkit-1.1"
export WEBKIT_INJECTED_BUNDLE_PATH="$ENGINE/lib/wpe-webkit-1.1/injected-bundle"
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export WEBKIT_FORCE_COMPOSITING_MODE=1 WEBKIT_FORCE_SANDBOX=0
export LD_PRELOAD="$D/lib/glx-stub.so"
export MUOS_DEBUG=1 WEBKIT_DEBUG=Process G_MESSAGES_DEBUG=all
mkdir -p /run/moonrider "\$XDG_CACHE_HOME"
rm -f "\$GST_REGISTRY" 2>/dev/null || true
echo "[mr-ctl] variant=$VARIANT engine=$ENGINE" >> "$RUNLOG"
# Run with a hard time limit. timeout sends TERM (never KILL) at expiry.
timeout ${SECS} "$D/bin/moonrider-launch" "file://$GAMEDIR/game/index.html" >> "$RUNLOG" 2>&1
GAME_RC=\$?
# Restore frontend: thaw if we froze it, else normal start.
rm -f "\$SAFE_QUIT" 2>/dev/null || true
unset LD_PRELOAD LIBGL_FB LIBGL_ES
unset WPE_BACKEND WPE_BACKEND_LIBRARY WPE_MALI_FBDEV_WIDTH WPE_MALI_FBDEV_HEIGHT
unset WEBKIT_EXEC_PATH WEBKIT_INJECTED_BUNDLE_PATH WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS
unset WEBKIT_FORCE_COMPOSITING_MODE WEBKIT_FORCE_SANDBOX WEBKIT_GST_DISABLE_GL_SINK WEBKIT_DEBUG
unset GST_PLUGIN_SYSTEM_PATH GST_PLUGIN_PATH GST_PLUGIN_SYSTEM_PATH_1_0 GST_PLUGIN_PATH_1_0
unset GST_REGISTRY GST_REGISTRY_FORK GST_REGISTRY_UPDATE
unset G_MESSAGES_DEBUG G_DEBUG MALLOC_CHECK_ MUOS_AUDIO_SOCK MUOS_DEBUG XDG_CACHE_HOME
export LD_LIBRARY_PATH="\$FRONTEND_LD_LIBRARY_PATH"
if [ -n "\$FROZEN_PIDS" ]; then
  for PID in \$FROZEN_PIDS; do kill -CONT "\$PID" 2>/dev/null || true; done
  I=3
  while FRONTEND_RUNNING && [ "\$I" -gt 0 ]; do
    sleep 1
    I=\$((I - 1))
  done
fi
if ! FRONTEND_RUNNING; then
  . /opt/muos/script/var/func.sh 2>/dev/null && FRONTEND start launcher 2>/dev/null
fi
I=10
while ! pidof muxfrontend >/dev/null 2>&1 && [ "\$I" -gt 0 ]; do
  sleep 1
  I=\$((I - 1))
done
if pidof muxfrontend >/dev/null 2>&1; then
  echo "[mr-ctl] frontend=running" >> "$RUNLOG"
else
  echo "[mr-ctl] frontend=FAILED" >> "$RUNLOG"
fi
echo "[mr-ctl] exit=\$GAME_RC" >> "$RUNLOG"
exit "\$GAME_RC"
INNER
    chmod +x "$RUNNER"
    # nohup + setsid + stdio fully redirected + background = immune to SSH SIGHUP.
    nohup setsid "$RUNNER" </dev/null >/dev/null 2>&1 &
    echo "  launched detached (pid $!); log builds at $RUNLOG"
    echo "  poll with: mr-ctl.sh $LOGCMD   (wait up to ~$((SECS + 14))s)"
    ;;
  kill)
    echo "== mr-ctl kill =="
    mr_kill
    frontend_start
    ;;
  status)
    echo "== mr-ctl status =="
    for p in moonrider-launch WPEWebProcess WPENetworkProcess; do
      PIDS=$(proc_pids "$p")
      if [ -n "$PIDS" ]; then
        for pid in $PIDS; do echo "  $p: running pid=$pid"; done
      else
        echo "  $p: not running"
      fi
    done
    pidof muxfrontend >/dev/null 2>&1 && echo "  frontend: running" || echo "  frontend: NOT running"
    h1=$(md5sum /dev/fb0 2>/dev/null | cut -d' ' -f1)
    sleep 3
    h2=$(md5sum /dev/fb0 2>/dev/null | cut -d' ' -f1)
    [ "$h1" != "$h2" ] && echo "  fb0: CHANGING (rendering)" || echo "  fb0: static"
    ;;
  log|log42)
    N="${2:-80}"
    READLOG="$LOG"
    [ "$1" = log42 ] && READLOG="$LOG42"
    grep -vE 'frame_will_render|frame_rendered|CHUNK' "$READLOG" 2>/dev/null | tail -"$N"
    ;;
  rawlog|rawlog42)
    READLOG="$LOG"
    [ "$1" = rawlog42 ] && READLOG="$LOG42"
    echo "== $READLOG =="
    tail -120 "$READLOG" 2>/dev/null
    ;;
  *)
    echo "usage: mr-ctl.sh {run|run42 [secs]|kill|status|log|log42 [n]|rawlog|rawlog42}"
    ;;
esac
