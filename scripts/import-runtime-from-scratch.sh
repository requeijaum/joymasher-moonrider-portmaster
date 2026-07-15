#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-/tmp/wpe-spike/runtime}"
DST="$ROOT/runtime"

if [[ ! -d "$SRC" ]]; then
  echo "runtime source not found: $SRC" >&2
  echo "Expected a prepared WPE runtime tree with bin/, lib/, libs/, gst-plugins/ and run-moonrider.sh." >&2
  exit 2
fi
mkdir -p "$DST"
for item in bin lib libs gst-plugins run-moonrider.sh; do
  if [[ -e "$SRC/$item" ]]; then
    rm -rf "$DST/$item"
    cp -a "$SRC/$item" "$DST/$item"
  fi
done
chmod +x "$DST/run-moonrider.sh" "$DST/bin/"* 2>/dev/null || true
find "$DST" -maxdepth 2 -type f -print | sort
