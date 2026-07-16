#!/bin/bash
# Build an asset-free PortMaster ZIP from an approved, populated staging tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="${STAGING:-$ROOT}"
OUT="${MOONRIDER_OUT:-/tmp/Moonrider-PortMaster-BYO.zip}"

required=(
  Moonrider.sh
  port.json
  moonrider/ASSETS-HERE.txt
  moonrider/runtime/run-moonrider.sh
  moonrider/runtime/bin/moonrider-launch
  moonrider/runtime/lib/libWPEBackend-mali-fbdev.so
  moonrider/runtime/libs/libGL.so.1
  moonrider/runtime/lib/wpe-webkit-1.1/WPEWebProcess
)
for rel in "${required[@]}"; do
  [[ -f "$STAGING/$rel" ]] || {
    echo "Missing installable staging artifact: $rel" >&2
    exit 2
  }
done

shopt -s nullglob
wpe_libs=("$STAGING"/moonrider/runtime/libs/libWPEWebKit-1.1.so*)
(( ${#wpe_libs[@]} > 0 )) || {
  echo "Missing installable staging artifact: runtime/libs/libWPEWebKit-1.1.so*" >&2
  exit 2
}

for rel in \
  moonrider/runtime/bin/moonrider-launch \
  moonrider/runtime/lib/libWPEBackend-mali-fbdev.so \
  moonrider/runtime/libs/libGL.so.1 \
  moonrider/runtime/lib/wpe-webkit-1.1/WPEWebProcess; do
  file "$STAGING/$rel" | grep -q 'ARM aarch64' || {
    echo "Runtime artifact is not an aarch64 binary: $rel" >&2
    exit 2
  }
done
file "${wpe_libs[0]}" | grep -q 'ARM aarch64' || {
  echo "libWPEWebKit is not an aarch64 binary" >&2
  exit 2
}

[[ -x "$STAGING/Moonrider.sh" ]] || chmod +x "$STAGING/Moonrider.sh"
[[ -x "$STAGING/moonrider/runtime/run-moonrider.sh" ]] || \
  chmod +x "$STAGING/moonrider/runtime/run-moonrider.sh"

case "$(realpath -m "$OUT")" in
  "$(realpath "$STAGING")"/*)
    echo "Output cannot be inside staging: $OUT" >&2
    exit 2
    ;;
esac

rm -f "$OUT" "$OUT.sha256"
(
  cd "$STAGING"
  zip -Xqr "$OUT" Moonrider.sh port.json moonrider \
    -x 'moonrider/game/*' 'moonrider/log.txt' 'moonrider/.xdg/*' \
       '*__pycache__*' '*.pyc' '*.bak'
)

unzip -tq "$OUT" >/dev/null
LIST=$(mktemp /tmp/moonrider-zip-list.XXXXXX)
trap 'rm -f "$LIST"' EXIT
unzip -Z1 "$OUT" > "$LIST"
for rel in \
  Moonrider.sh \
  port.json \
  moonrider/ASSETS-HERE.txt \
  moonrider/runtime/run-moonrider.sh \
  moonrider/runtime/bin/moonrider-launch; do
  grep -qx "$rel" "$LIST" || {
    echo "Required package entry absent: $rel" >&2
    exit 1
  }
done
if grep -q '^moonrider/game/.*[^/]$' "$LIST"; then
  echo "BYO package leaked game files" >&2
  exit 1
fi

sha256sum "$OUT" > "$OUT.sha256"
printf 'Built installable BYO package: %s\n' "$OUT"
cat "$OUT.sha256"
