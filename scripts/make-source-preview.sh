#!/bin/bash
# Build a deterministic source/BYO preview from a committed git ref.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-v0.1.0-alpha.1}"
SOURCE_REF="${SOURCE_REF:-HEAD}"
OUT_DIR="${OUT_DIR:-/tmp/moonrider-source-preview}"
NAME="Moonrider-PortMaster-${VERSION#v}-source"
ZIP="$OUT_DIR/$NAME.zip"
FILES="$OUT_DIR/$NAME-files.sha256"
SUMS="$OUT_DIR/SHA256SUMS"

cd "$ROOT"
git rev-parse --verify "${SOURCE_REF}^{tree}" >/dev/null
mkdir -p "$OUT_DIR"
for output in "$ZIP" "$FILES" "$SUMS"; do
  if [[ -e "$output" ]]; then
    echo "Refusing to overwrite existing artifact: $output" >&2
    exit 2
  fi
done

# Refuse commercial payloads or imported runtime binaries even if someone adds
# them to a future release commit by mistake.
TREE=$(mktemp /tmp/moonrider-source-tree.XXXXXX)
if [[ "${KEEP_TEST_TMP:-0}" = 1 ]]; then
  echo "preserving source tree list: $TREE" >&2
else
  trap 'rm -f "$TREE"' EXIT
fi
git ls-tree -r --name-only "$SOURCE_REF" > "$TREE"
if grep -q '^moonrider/game/' "$TREE"; then
  echo 'Refusing source preview: moonrider/game payload is tracked.' >&2
  exit 1
fi
if grep '^moonrider/runtime/' "$TREE" | grep -qv '^moonrider/runtime/README.md$'; then
  echo 'Refusing source preview: imported runtime binary is tracked.' >&2
  exit 1
fi
if grep -Ei '\.(ogg|mp3|wav|mp4|webm|asar|exe)$' "$TREE"; then
  echo 'Refusing source preview: forbidden game/binary asset extension.' >&2
  exit 1
fi

PREFIX="moonrider-portmaster-${VERSION#v}/"
git archive --format=zip --prefix="$PREFIX" --output="$ZIP" "$SOURCE_REF"
unzip -tq "$ZIP" >/dev/null

python3 - "$ZIP" "$FILES" <<'PY'
from hashlib import sha256
from pathlib import Path
from zipfile import ZipFile
import sys
archive, output = map(Path, sys.argv[1:])
with ZipFile(archive) as zf, output.open('w', encoding='utf-8') as out:
    for info in sorted(zf.infolist(), key=lambda item: item.filename):
        if info.is_dir():
            continue
        out.write(f"{sha256(zf.read(info)).hexdigest()}  {info.filename}\n")
PY

(
  cd "$OUT_DIR"
  sha256sum "$(basename "$ZIP")" "$(basename "$FILES")" > "$(basename "$SUMS")"
)

printf 'Built source/BYO preview from %s (%s)\n' "$SOURCE_REF" "$(git rev-parse "$SOURCE_REF")"
printf '%s\n' "$ZIP" "$FILES" "$SUMS"
cat "$SUMS"
