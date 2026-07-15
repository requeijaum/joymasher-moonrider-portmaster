#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
RUN="$ROOT/runtime-config/run-moonrider.sh"

grep -F 'ENGINE="${MOONRIDER_WPE_ENGINE_DIR:-$HERE}"' "$RUN" >/dev/null
grep -F 'export LD_LIBRARY_PATH="$ENGINE/libs:$HERE/libs:$HERE/lib:/usr/lib/gl4es:/usr/lib:/lib"' "$RUN" >/dev/null
grep -F 'export WEBKIT_EXEC_PATH="$ENGINE/lib/wpe-webkit-1.1"' "$RUN" >/dev/null
grep -F 'export WEBKIT_INJECTED_BUNDLE_PATH="$ENGINE/lib/wpe-webkit-1.1/injected-bundle"' "$RUN" >/dev/null

echo "test-wpe-engine-overlay: OK"
