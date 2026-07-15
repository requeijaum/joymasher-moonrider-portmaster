#!/bin/bash
# Build a PortMaster/HarbourMaster zip from an explicit staging tree.
#
# Required staging layout:
#   Moonrider.sh
#   port.json
#   moonrider/runtime/
#   moonrider/game/          optional for canonical BYO release
#
# Env:
#   STAGING=/tmp/moonrider-release-stage
#   MOONRIDER_OUT=/tmp/Moonrider-BYO.zip
#   MOONRIDER_INCLUDE_GAME=0   default; never redistributes proprietary assets
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="${STAGING:-$ROOT}"
OUT="${MOONRIDER_OUT:-/tmp/Moonrider-BYO.zip}"
INCLUDE_GAME="${MOONRIDER_INCLUDE_GAME:-0}"

for f in Moonrider.sh port.json moonrider/runtime/run-moonrider.sh; do
  [[ -e "$STAGING/$f" ]] || { echo "Missing staging artifact: $STAGING/$f" >&2; exit 2; }
done
[[ -x "$STAGING/Moonrider.sh" ]] || chmod +x "$STAGING/Moonrider.sh"
[[ "$INCLUDE_GAME" = 0 || "$INCLUDE_GAME" = 1 ]] || { echo "MOONRIDER_INCLUDE_GAME must be 0 or 1" >&2; exit 2; }

# Output must stay outside the staging tree to avoid recursively packaging itself.
case "$(realpath -m "$OUT")" in
  "$(realpath "$STAGING")"/*) echo "Output cannot be inside staging: $OUT" >&2; exit 2 ;;
esac

rm -f "$OUT"
EXCLUDES=(-x 'moonrider/log.txt' 'moonrider/.xdg/*' '*__pycache__*' '*.pyc' '*.bak')
if [[ "$INCLUDE_GAME" != 1 ]]; then
  EXCLUDES+=(-x 'moonrider/game/*')
fi

(
  cd "$STAGING"
  zip -qr "$OUT" Moonrider.sh port.json moonrider "${EXCLUDES[@]}"
)

# Release assertions.
unzip -tq "$OUT" >/dev/null
LIST=$(mktemp /tmp/moonrider-zip-list.XXXXXX)
trap 'rm -f "$LIST"' EXIT
unzip -Z1 "$OUT" > "$LIST"
grep -qx 'Moonrider.sh' "$LIST" || { echo "Launcher absent from zip" >&2; exit 1; }
grep -qx 'port.json' "$LIST" || { echo "port.json absent from zip" >&2; exit 1; }
grep -qx 'moonrider/runtime/run-moonrider.sh' "$LIST" || { echo "Runtime absent from zip" >&2; exit 1; }
if [[ "$INCLUDE_GAME" != 1 ]] && grep -q '^moonrider/game/.*\.' "$LIST"; then
  echo "BYO release leaked game files" >&2; exit 1
fi

sha256sum "$OUT" > "$OUT.sha256"
printf 'Built: %s\n' "$OUT"
du -h "$OUT"
cat "$OUT.sha256"
