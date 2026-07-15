#!/bin/bash
# Extract the Construct 2 / HTML5 game assets from a legitimate copy of
# Vengeful Guardian: Moonrider into moonrider/game/.
#
# Usage: scripts/extract-assets.sh /path/to/game/assets
#
# The "game assets folder" is the one containing c2runtime.js, data.js, media/,
# images/, the *.csv files and the intro video. Nothing here is redistributed —
# assets stay under moonrider/game/ which is gitignored.

set -euo pipefail

SRC="${1:-}"
if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
  echo "Usage: $0 /path/to/game/assets" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/moonrider/game"
mkdir -p "$DEST"

echo "Copying game assets:"
echo "  from: $SRC"
echo "  to:   $DEST"

# Core C2 runtime + data + asset folders
for item in c2runtime.js data.js index.html images media; do
  if [ -e "$SRC/$item" ]; then
    cp -a "$SRC/$item" "$DEST/"
    echo "  + $item"
  else
    echo "  ! missing: $item" >&2
  fi
done

# CSV localization / config files
cp -a "$SRC"/*.csv "$DEST/" 2>/dev/null && echo "  + *.csv" || true

# Intro video (mandatory — engine waits on it before the menu / audio unlock)
cp -a "$SRC"/*.mp4 "$DEST/" 2>/dev/null && echo "  + *.mp4" || true

echo "Done. Verify with scripts/verify-assets.sh (TODO)."
