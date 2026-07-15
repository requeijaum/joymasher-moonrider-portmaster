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

frontend_stop() { . /opt/muos/script/var/func.sh 2>/dev/null && FRONTEND stop 2>/dev/null; }
frontend_start() { . /opt/muos/script/var/func.sh 2>/dev/null && FRONTEND start 2>/dev/null; }

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
# --- robust frontend teardown ---------------------------------------------
# muOS FRONTEND stop sends SIGUSR1 and only makes muxfrontend actually EXIT
# when \$SAFE_QUIT is set (it writes that flag-file so the frontend's own
# signal handler knows the quit is intentional). Launched over SSH we don't
# inherit the muOS env, so we must provide SAFE_QUIT ourselves.
export SAFE_QUIT=/run/muos_safe_quit
: > "\$SAFE_QUIT" 2>/dev/null || true
. /opt/muos/script/var/func.sh 2>/dev/null && FRONTEND stop 2>/dev/null
# Fallback: if muxfrontend survived (SAFE_QUIT path failed), FREEZE it so it
# releases the framebuffer without being killed/restarted (SIGCONT at the end).
FRONTEND_FROZEN=""
if pidof muxfrontend >/dev/null 2>&1; then
  kill -STOP "\$(pidof muxfrontend)" 2>/dev/null && FRONTEND_FROZEN=1
fi
sleep 1
cd "$D"
export LD_LIBRARY_PATH="$D/libs:$D/lib:/usr/lib/gl4es:/usr/lib:/lib"
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
# Restore frontend: thaw if we froze it, else normal start.
if [ -n "\$FRONTEND_FROZEN" ] && pidof muxfrontend >/dev/null 2>&1; then
  kill -CONT "\$(pidof muxfrontend)" 2>/dev/null
else
  . /opt/muos/script/var/func.sh 2>/dev/null && FRONTEND start 2>/dev/null
fi
rm -f "\$SAFE_QUIT" 2>/dev/null || true
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
