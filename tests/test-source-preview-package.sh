#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d /tmp/moonrider-source-preview-test.XXXXXX)
if [[ "${KEEP_TEST_TMP:-0}" = 1 ]]; then
  echo "preserving test directory: $TMP" >&2
else
  trap 'rm -rf "$TMP"' EXIT
fi

VERSION="${VERSION:-v0.1.0-alpha.1}"
OUT_DIR="$TMP" SOURCE_REF="${SOURCE_REF:-HEAD}" VERSION="$VERSION" \
  bash "$ROOT/scripts/make-source-preview.sh" >/dev/null

ZIP="$TMP/Moonrider-PortMaster-${VERSION#v}-source.zip"
SUMS="$TMP/SHA256SUMS"
FILES="$TMP/Moonrider-PortMaster-${VERSION#v}-source-files.sha256"

[[ -s "$ZIP" && -s "$SUMS" && -s "$FILES" ]]
(cd "$TMP" && sha256sum -c SHA256SUMS >/dev/null)
unzip -tq "$ZIP" >/dev/null
LIST="$TMP/list.txt"
unzip -Z1 "$ZIP" > "$LIST"

grep -q '/LICENSE$' "$LIST"
grep -q '/THIRD_PARTY_NOTICES.md$' "$LIST"
grep -q '/README.md$' "$LIST"
grep -q '/native/backend/moonrider-launch.c$' "$LIST"
! grep -qE '/moonrider/game/|/moonrider/runtime/.+\.(so|bin)$|/\.git/' "$LIST"
! unzip -p "$ZIP" "*/README.md" | grep -qE '192\.168\.1\.[0-9]+'

echo 'test-source-preview-package: OK'
