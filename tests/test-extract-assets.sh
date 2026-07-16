#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d /tmp/moonrider-extract-test.XXXXXX)
echo "preserving extraction test: $TMP"
SRC="$TMP/source"
DEST="$TMP/game"
mkdir -p "$SRC/images" "$SRC/media"
printf '<script src="c2runtime.js"></script>\n' > "$SRC/index.html"
printf 'runtime\n' > "$SRC/c2runtime.js"
printf 'data\n' > "$SRC/data.js"
printf 'image\n' > "$SRC/images/a.png"
printf 'audio\n' > "$SRC/media/a.ogg"
printf 'csv\n' > "$SRC/en.csv"
printf 'video\n' > "$SRC/intro.mp4"

MOONRIDER_GAME_DEST="$DEST" bash "$ROOT/scripts/extract-assets.sh" "$SRC" >/dev/null
for rel in index.html c2runtime.js data.js images/a.png media/a.ogg en.csv intro.mp4; do
  cmp -s "$SRC/$rel" "$DEST/$rel" || {
    echo "extractor changed or omitted: $rel" >&2
    exit 1
  }
done
if grep -Rqs 'MOONRIDER-MUOS-LAYER\|muos_audio_ghost\|muos_gamepad_shim' "$DEST"; then
  echo 'extractor modified raw game assets' >&2
  exit 1
fi
if MOONRIDER_GAME_DEST="$DEST" bash "$ROOT/scripts/extract-assets.sh" "$SRC" >/dev/null 2>&1; then
  echo 'extractor merged into an existing destination' >&2
  exit 1
fi
INCOMPLETE="$TMP/incomplete"
mkdir -p "$INCOMPLETE"
printf '<html></html>\n' > "$INCOMPLETE/index.html"
if MOONRIDER_GAME_DEST="$TMP/incomplete-out" \
  bash "$ROOT/scripts/extract-assets.sh" "$INCOMPLETE" >/dev/null 2>&1; then
  echo 'extractor accepted an incomplete game export' >&2
  exit 1
fi
printf 'test-extract-assets: OK\n'
