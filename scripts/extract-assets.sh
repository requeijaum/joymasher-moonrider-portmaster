#!/bin/bash
# Copy a legitimate Construct 2 desktop export into a new staging directory.
# The export remains unchanged; moonrider-launch injects the compatibility layer.
set -euo pipefail

SRC="${1:-}"
if [[ -z "$SRC" || ! -d "$SRC" ]]; then
  echo "Usage: $0 /path/to/game/assets" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${MOONRIDER_GAME_DEST:-$ROOT/moonrider/game}"
SRC_ABS="$(cd "$SRC" && pwd)"

[[ ! -e "$DEST" ]] || {
  echo "Refusing to merge with an existing destination: $DEST" >&2
  exit 2
}

missing=0
for item in index.html c2runtime.js data.js images media; do
  if [[ ! -e "$SRC_ABS/$item" ]]; then
    echo "Missing required game export item: $item" >&2
    missing=1
  fi
done
compgen -G "$SRC_ABS/*.csv" >/dev/null || {
  echo "Missing required CSV files" >&2
  missing=1
}
compgen -G "$SRC_ABS/*.mp4" >/dev/null || {
  echo "Missing required intro MP4" >&2
  missing=1
}
(( missing == 0 )) || exit 2

mkdir -p "$DEST"
# Copy the complete desktop export, not merely the minimum validation set.
# index.html commonly references files such as jquery, manifests and icons that
# are outside images/ and media/. Omitting them produces a subtly broken port.
cp -a "$SRC_ABS"/. "$DEST"/

printf 'Copied unchanged game export:\n  from: %s\n  to:   %s\n' "$SRC_ABS" "$DEST"
printf 'The WPE launcher will inject moonrider/patches at document start.\n'
