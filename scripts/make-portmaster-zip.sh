#!/bin/bash
# Build the PortMaster/HarbourMaster zip from the port tree.
# Produces Moonrider.zip, ready to drop into /roms/ports (or install via PortMaster).
#
# Env overrides (used for off-SSD staging in /tmp tmpfs):
#   MOONRIDER_OUT=/tmp/Moonrider.zip     where to write the zip (default: repo root)
#   MOONRIDER_INCLUDE_GAME=1             include moonrider/game/ assets in the zip
#                                        (default: excluded — canonical BYO-assets zip)
#   MOONRIDER_FOLLOW_LINKS=1             dereference symlinks when archiving
#                                        (needed when game/ is a symlink to the source)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${MOONRIDER_OUT:-$ROOT/Moonrider.zip}"
INCLUDE_GAME="${MOONRIDER_INCLUDE_GAME:-0}"
FOLLOW_LINKS="${MOONRIDER_FOLLOW_LINKS:-0}"

rm -f "$OUT"
echo "Packaging $OUT ..."

ZIP_OPTS="-r"
[ "$FOLLOW_LINKS" = "1" ] && ZIP_OPTS="-r -y"   # -y stores symlinks... we want the
# opposite (follow them). zip has no "follow" flag, so when FOLLOW_LINKS=1 we
# archive from a copy-free staging tree assembled by the caller instead. Here we
# just make sure -y is NOT set so zip dereferences links by default.
[ "$FOLLOW_LINKS" = "1" ] && ZIP_OPTS="-r"

EXCLUDES=(-x 'moonrider/log.txt' -x 'moonrider/.xdg/*' -x '*__pycache__*' -x '*.pyc')
if [ "$INCLUDE_GAME" != "1" ]; then
  EXCLUDES+=(-x 'moonrider/game/*')
fi

zip $ZIP_OPTS "$OUT" \
    Moonrider.sh \
    moonrider \
    "${EXCLUDES[@]}"

echo "Built $OUT"
ls -lh "$OUT"
echo "--- contents (first/last) ---"
unzip -l "$OUT" | head -8
echo "..."
unzip -l "$OUT" | tail -4
