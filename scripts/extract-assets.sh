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

# Destination is overridable so a build can stage assets OFF the SSD (e.g. in
# /tmp tmpfs) instead of writing into the repo's moonrider/game/.
#   MOONRIDER_GAME_DEST=/tmp/... scripts/extract-assets.sh <src>
DEST="${MOONRIDER_GAME_DEST:-$ROOT/moonrider/game}"

# MOONRIDER_LINK=1 symlinks the whole asset tree instead of copying it — zero
# bytes written to disk beyond the link. Packaging must traverse with `find -L`.
LINK="${MOONRIDER_LINK:-0}"

SRC_ABS="$(cd "$SRC" && pwd)"

if [ "$LINK" = "1" ]; then
  mkdir -p "$(dirname "$DEST")"
  rm -rf "$DEST"
  ln -s "$SRC_ABS" "$DEST"
  echo "Linked game assets (no copy):"
  echo "  $DEST -> $SRC_ABS"
  echo "Done. (symlink mode — package with 'find -L')."
  exit 0
fi

mkdir -p "$DEST"
echo "Copying game assets:"
echo "  from: $SRC_ABS"
echo "  to:   $DEST"

# Core C2 runtime + data + asset folders
for item in c2runtime.js data.js index.html images media; do
  if [ -e "$SRC_ABS/$item" ]; then
    cp -a "$SRC_ABS/$item" "$DEST/"
    echo "  + $item"
  else
    echo "  ! missing: $item" >&2
  fi
done

# CSV localization / config files
cp -a "$SRC_ABS"/*.csv "$DEST/" 2>/dev/null && echo "  + *.csv" || true

# Intro video (mandatory — engine waits on it before the menu / audio unlock)
cp -a "$SRC_ABS"/*.mp4 "$DEST/" 2>/dev/null && echo "  + *.mp4" || true

echo "Done. Verify with scripts/verify-assets.sh (TODO)."
