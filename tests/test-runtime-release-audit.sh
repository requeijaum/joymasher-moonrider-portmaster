#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d /tmp/moonrider-runtime-audit-test.XXXXXX)
if [[ "${KEEP_TEST_TMP:-0}" = 1 ]]; then
  echo "preserving test directory: $TMP" >&2
else
  trap 'rm -rf "$TMP"' EXIT
fi

python3 - "$TMP/unsafe.zip" <<'PY'
from zipfile import ZipFile
import sys
with ZipFile(sys.argv[1], 'w') as z:
    z.writestr('runtime/bin/tool', b'\x7fELF' + b'\0' * 64)
PY

set +e
python3 "$ROOT/scripts/audit-runtime-release.py" "$TMP/unsafe.zip" --output "$TMP/report.json"
rc=$?
set -e
[[ $rc -ne 0 ]]
python3 - "$TMP/report.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r['release_eligible'] is False
assert r['elf_files'] == 1
assert 'missing license bundle' in r['blockers']
assert 'missing source provenance' in r['blockers']
PY

echo 'test-runtime-release-audit: OK'
