#!/bin/bash
# Build an asset-free PortMaster ZIP from an approved, populated staging tree.
set -euo pipefail
export TZ=UTC

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="${STAGING:-$ROOT}"
OUT="${MOONRIDER_OUT:-/tmp/moonrider.zip}"

required=(
  Moonrider.sh
  moonrider/port.json
  moonrider/gameinfo.xml
  moonrider/ASSETS-HERE.txt
  moonrider/patches/muos_gamepad_shim.js
  moonrider/patches/muos_audio_ghost.js
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

launcher="$STAGING/moonrider/runtime/bin/moonrider-launch"
for marker in MOONRIDER_SHIM_DIR muos_gamepad_shim.js muos_audio_ghost.js; do
  grep -qa "$marker" "$launcher" || {
    echo "Launcher lacks required BYO runtime-shim support: $marker" >&2
    exit 2
  }
done

for rel in Moonrider.sh moonrider/runtime/run-moonrider.sh; do
  mode=$(stat -c '%a' "$STAGING/$rel")
  [[ "$mode" = 755 ]] || {
    echo "Executable must be mode 0755 in approved staging: $rel (got $mode)" >&2
    exit 2
  }
done

case "$(realpath -m "$OUT")" in
  "$(realpath "$STAGING")"/*)
    echo "Output cannot be inside staging: $OUT" >&2
    exit 2
    ;;
esac

if [[ -e "$OUT" || -e "$OUT.sha256" || -e "$OUT.manifest.sha256" ]]; then
  echo "Refusing to overwrite existing output or checksum sidecar: $OUT" >&2
  exit 2
fi
(
  cd "$STAGING"
  zip -Xqr "$OUT" Moonrider.sh moonrider \
    -x 'moonrider/game/*' 'moonrider/log.txt' 'moonrider/.xdg/*' \
       '*__pycache__*' '*.pyc' '*.bak'
)

unzip -tq "$OUT" >/dev/null
LIST=$(unzip -Z1 "$OUT")
for rel in \
  Moonrider.sh \
  moonrider/port.json \
  moonrider/gameinfo.xml \
  moonrider/ASSETS-HERE.txt \
  moonrider/patches/muos_gamepad_shim.js \
  moonrider/patches/muos_audio_ghost.js \
  moonrider/runtime/run-moonrider.sh \
  moonrider/runtime/bin/moonrider-launch; do
  grep -qx "$rel" <<<"$LIST" || {
    echo "Required package entry absent: $rel" >&2
    exit 1
  }
done
if grep -q '^moonrider/game/.*[^/]$' <<<"$LIST"; then
  echo "BYO package leaked game files" >&2
  exit 1
fi

python3 - "$OUT" "$OUT.manifest.sha256" <<'PY'
from pathlib import PurePosixPath
import hashlib, stat, sys, zipfile

archive, manifest = sys.argv[1:]
seen = set()
lines = []
with zipfile.ZipFile(archive) as zf:
    for info in zf.infolist():
        path = PurePosixPath(info.filename)
        normalized = str(path)
        if path.is_absolute() or ".." in path.parts or normalized in seen:
            raise SystemExit(f"unsafe/duplicate ZIP entry: {info.filename}")
        seen.add(normalized)
        mode = (info.external_attr >> 16) & 0xFFFF
        if stat.S_ISLNK(mode):
            raise SystemExit(f"symlink forbidden in PortMaster ZIP: {info.filename}")
        if not info.is_dir():
            lines.append(f"{hashlib.sha256(zf.read(info)).hexdigest()}  {normalized}")
open(manifest, "w", encoding="utf-8", newline="\n").write("\n".join(sorted(lines)) + "\n")
PY

OUT_NAME=$(basename "$OUT")
OUT_HASH=$(sha256sum "$OUT" | cut -d' ' -f1)
printf '%s  %s\n' "$OUT_HASH" "$OUT_NAME" > "$OUT.sha256"
printf 'Built installable BYO package: %s\n' "$OUT"
cat "$OUT.sha256"
