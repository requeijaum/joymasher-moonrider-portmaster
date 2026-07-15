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
REF="${SOURCE_REF:-HEAD}"
UTC_OUT="$TMP/utc"
OTHER_OUT="$TMP/other-tz"
EXTRACT="$TMP/extracted"
mkdir -p "$UTC_OUT" "$OTHER_OUT" "$EXTRACT"

TZ=UTC OUT_DIR="$UTC_OUT" SOURCE_REF="$REF" VERSION="$VERSION" \
  bash "$ROOT/scripts/make-source-preview.sh" >/dev/null
TZ=Pacific/Honolulu OUT_DIR="$OTHER_OUT" SOURCE_REF="$REF" VERSION="$VERSION" \
  bash "$ROOT/scripts/make-source-preview.sh" >/dev/null

NAME="Moonrider-PortMaster-${VERSION#v}-source"
ZIP="$UTC_OUT/$NAME.zip"
SUMS="$UTC_OUT/SHA256SUMS"
FILES="$UTC_OUT/$NAME-files.sha256"

[[ -s "$ZIP" && -s "$SUMS" && -s "$FILES" ]]
(cd "$UTC_OUT" && sha256sum -c SHA256SUMS >/dev/null)
cmp -s "$ZIP" "$OTHER_OUT/$NAME.zip"
cmp -s "$FILES" "$OTHER_OUT/$NAME-files.sha256"
unzip -tq "$ZIP" >/dev/null
unzip -q "$ZIP" -d "$EXTRACT"
(cd "$EXTRACT" && sha256sum -c "$FILES" >/dev/null)
LIST="$TMP/list.txt"
unzip -Z1 "$ZIP" > "$LIST"

grep -q '/LICENSE$' "$LIST"
grep -q '/THIRD_PARTY_NOTICES.md$' "$LIST"
grep -q '/README.md$' "$LIST"
grep -q '/native/backend/moonrider-launch.c$' "$LIST"
! grep -qE '/moonrider/game/|/moonrider/runtime/.+\.(so|bin)$|/\.git/' "$LIST"
! unzip -p "$ZIP" "*/README.md" | grep -qE '192\.168\.1\.[0-9]+'

echo 'test-source-preview-package: OK'
