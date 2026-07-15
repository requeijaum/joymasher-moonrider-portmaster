#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CTL="$ROOT/scripts/mr-ctl.sh"

grep -F 'run|run42)' "$CTL" >/dev/null
grep -F 'ENGINE=/mnt/mmc/moonrider-wpe-2.42' "$CTL" >/dev/null
grep -F 'libWPEWebKit-1.1.so.0" ]' "$CTL" >/dev/null
if grep -F 'libWPEWebKit-1.1.so.0.6.5" ]' "$CTL" >/dev/null; then
  echo "controller must check the SONAME file, not a symlink target" >&2
  exit 1
fi
grep -F 'export LD_LIBRARY_PATH="$ENGINE/libs:$D/libs:$D/lib:/usr/lib/gl4es:/usr/lib:/lib"' "$CTL" >/dev/null
grep -F 'export WEBKIT_EXEC_PATH="$ENGINE/lib/wpe-webkit-1.1"' "$CTL" >/dev/null
grep -F 'export WEBKIT_INJECTED_BUNDLE_PATH="$ENGINE/lib/wpe-webkit-1.1/injected-bundle"' "$CTL" >/dev/null
grep -F 'moonrider-diag-2.42.log' "$CTL" >/dev/null
grep -F 'FRONTEND start launcher' "$CTL" >/dev/null
grep -F 'SAFE_QUIT=/tmp/safe_quit' "$CTL" >/dev/null
if grep -F '/run/muos_safe_quit' "$CTL" >/dev/null; then
  echo "controller must use the SAFE_QUIT path defined by muOS" >&2
  exit 1
fi
grep -F 'log builds at $RUNLOG' "$CTL" >/dev/null
grep -F 'FRONTEND_LD_LIBRARY_PATH="\$LD_LIBRARY_PATH"' "$CTL" >/dev/null
grep -F 'export LD_LIBRARY_PATH="\$FRONTEND_LD_LIBRARY_PATH"' "$CTL" >/dev/null
grep -F 'unset LD_PRELOAD' "$CTL" >/dev/null
grep -F 'unset WPE_BACKEND WPE_BACKEND_LIBRARY' "$CTL" >/dev/null
grep -F 'while ! pidof muxfrontend' "$CTL" >/dev/null
grep -F 'SIGNAL_FRONTEND USR1' "$CTL" >/dev/null
grep -F 'SIGNAL_FRONTEND TERM' "$CTL" >/dev/null
if grep -F 'FRONTEND stop 2>/dev/null' "$CTL" >/dev/null; then
  echo "controller must not call muOS FRONTEND stop because it contains a KILL fallback" >&2
  exit 1
fi

echo "test-mr-ctl-wpe42: OK"
