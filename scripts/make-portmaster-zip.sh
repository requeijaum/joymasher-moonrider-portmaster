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
  moonrider/patches/muos_frameskip.js
  moonrider/runtime/run-moonrider.sh
  moonrider/runtime/RUNTIME-MANIFEST.sha256
  moonrider/runtime/RUNTIME-PROVENANCE.md
  moonrider/runtime/bin/moonrider-launch
  moonrider/runtime/lib/libWPEBackend-mali-fbdev.so
  moonrider/runtime/lib/glx-stub.so
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
gst_plugins=("$STAGING"/moonrider/runtime/gst-plugins/*.so)
(( ${#gst_plugins[@]} >= 24 )) || {
  echo "Incomplete GStreamer runtime: expected at least 24 plugins, got ${#gst_plugins[@]}" >&2
  exit 2
}
for rel in libgstcoreelements.so libgstcoretracers.so; do
  [[ -f "$STAGING/moonrider/runtime/gst-plugins/$rel" ]] || {
    echo "Missing required GStreamer plugin: runtime/gst-plugins/$rel" >&2
    exit 2
  }
done

for rel in \
  moonrider/runtime/bin/moonrider-launch \
  moonrider/runtime/lib/libWPEBackend-mali-fbdev.so \
  moonrider/runtime/lib/glx-stub.so \
  moonrider/runtime/libs/libGL.so.1 \
  moonrider/runtime/lib/wpe-webkit-1.1/WPEWebProcess; do
  file "$STAGING/$rel" | grep -q 'ARM aarch64' || {
    echo "Runtime artifact is not an aarch64 binary: $rel" >&2
    exit 2
  }
done
for plugin in "${gst_plugins[@]}"; do
  file "$plugin" | grep -q 'ARM aarch64' || {
    echo "GStreamer plugin is not an aarch64 binary: $plugin" >&2
    exit 2
  }
done

python3 - "$STAGING/moonrider/runtime" <<'PY'
from pathlib import Path, PurePosixPath
import hashlib, sys

runtime = Path(sys.argv[1])
manifest = runtime / "RUNTIME-MANIFEST.sha256"
declared = {}
for number, raw in enumerate(manifest.read_text(encoding="utf-8").splitlines(), 1):
    if not raw.strip():
        continue
    try:
        digest, rel = raw.split("  ", 1)
    except ValueError:
        raise SystemExit(f"invalid runtime manifest line {number}")
    path = PurePosixPath(rel)
    if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
        raise SystemExit(f"invalid SHA-256 on runtime manifest line {number}")
    if path.is_absolute() or ".." in path.parts or rel in declared:
        raise SystemExit(f"unsafe/duplicate runtime manifest path: {rel}")
    declared[rel] = digest

expected = {
    path.relative_to(runtime).as_posix()
    for path in runtime.rglob("*")
    if path.is_file() and path != manifest
}
if set(declared) != expected:
    missing = sorted(expected - set(declared))
    extra = sorted(set(declared) - expected)
    raise SystemExit(f"runtime manifest coverage mismatch; missing={missing}, extra={extra}")
for rel, expected_digest in declared.items():
    actual = hashlib.sha256((runtime / rel).read_bytes()).hexdigest()
    if actual != expected_digest:
        raise SystemExit(f"runtime manifest hash mismatch: {rel}")
licenses = runtime / "LICENSES"
if not licenses.is_dir() or not any(path.is_file() for path in licenses.rglob("*")):
    raise SystemExit("runtime LICENSES/ is missing or empty")
print("Runtime inventory hashes verified; provenance and license payload present")
PY

file "${wpe_libs[0]}" | grep -q 'ARM aarch64' || {
  echo "libWPEWebKit is not an aarch64 binary" >&2
  exit 2
}

launcher="$STAGING/moonrider/runtime/bin/moonrider-launch"
for marker in MOONRIDER_SHIM_DIR muos_gamepad_shim.js muos_audio_ghost.js muos_frameskip.js MOONRIDER_FRAMESKIP; do
  grep -qa "$marker" "$launcher" || {
    echo "Launcher lacks required BYO runtime-shim support: $marker" >&2
    exit 2
  }
done

for rel in Moonrider.sh moonrider/runtime/run-moonrider.sh; do
  [[ -x "$STAGING/$rel" ]] || {
    echo "Executable bit missing in approved staging: $rel" >&2
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
python3 - "$STAGING" "$OUT" <<'PY'
from pathlib import Path, PurePosixPath
import stat, sys, zipfile

stage, output = Path(sys.argv[1]), Path(sys.argv[2])

def excluded(rel: str) -> bool:
    parts = PurePosixPath(rel).parts
    return (
        parts[:2] == ("moonrider", "game")
        or parts[:2] == ("moonrider", ".xdg")
        or rel == "moonrider/log.txt"
        or "__pycache__" in parts
        or rel.endswith((".pyc", ".bak"))
    )

paths = [stage / "Moonrider.sh", *sorted((stage / "moonrider").rglob("*"))]
entries = []
commercial_suffixes = {
    ".ogg", ".mp3", ".wav", ".flac", ".m4a", ".aac", ".mp4",
    ".webm", ".png", ".jpg", ".jpeg", ".webp", ".asar", ".exe",
}
commercial_names = {"c2runtime.js", "data.js", "index.html"}
for path in paths:
    rel = path.relative_to(stage).as_posix()
    if excluded(rel):
        continue
    if path.is_symlink():
        raise SystemExit(f"symlink forbidden in PortMaster staging: {rel}")
    if path.is_file() and (
        path.suffix.lower() in commercial_suffixes
        or path.name.lower() in commercial_names
        or path.suffix.lower() == ".csv"
    ):
        raise SystemExit(f"commercial game payload forbidden outside game/: {rel}")
    entries.append((rel, path))

# Ensure a ready-to-fill BYO directory even when staging has no game/ directory.
entries.append(("moonrider/game", None))
entries.sort(key=lambda item: item[0])

with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for rel, path in entries:
        is_dir = path is None or path.is_dir()
        name = rel.rstrip("/") + ("/" if is_dir else "")
        info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
        info.create_system = 3
        if is_dir:
            info.compress_type = zipfile.ZIP_STORED
            info.external_attr = ((stat.S_IFDIR | 0o755) << 16) | 0x10
            zf.writestr(info, b"")
        else:
            mode = 0o755 if path.stat().st_mode & 0o111 else 0o644
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (stat.S_IFREG | mode) << 16
            zf.writestr(info, path.read_bytes())
PY

unzip -tq "$OUT" >/dev/null
LIST=$(unzip -Z1 "$OUT")
for rel in \
  Moonrider.sh \
  moonrider/port.json \
  moonrider/gameinfo.xml \
  moonrider/ASSETS-HERE.txt \
  moonrider/patches/muos_gamepad_shim.js \
  moonrider/patches/muos_audio_ghost.js \
  moonrider/patches/muos_frameskip.js \
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
