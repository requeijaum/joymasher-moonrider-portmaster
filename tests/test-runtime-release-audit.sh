#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d /tmp/moonrider-runtime-audit-test.XXXXXX)
if [[ "${KEEP_TEST_TMP:-0}" = 1 ]]; then
  echo "preserving test directory: $TMP" >&2
else
  trap 'rm -rf "$TMP"' EXIT
fi

python3 - "$TMP" <<'PY'
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo
import json, stat, sys
root = Path(sys.argv[1])
metadata = {
    'licenses/LICENSE.txt': b'license',
    'metadata/source_provenance.json': json.dumps({'source': 'fixture'}).encode(),
    'metadata/third_party_manifest.json': json.dumps({'components': []}).encode(),
}
with ZipFile(root/'unsafe.zip', 'w') as z:
    z.writestr('runtime/bin/tool', b'\x7fELF' + b'\0' * 64)
with ZipFile(root/'traversal.zip', 'w') as z:
    for name, data in metadata.items(): z.writestr(name, data)
    z.writestr('runtime/bin/tool', b'\x7fELF' + b'\0' * 64)
    z.writestr('../escape', b'not allowed')
with ZipFile(root/'compression-bomb.zip', 'w', compression=ZIP_DEFLATED) as z:
    z.writestr('runtime/share/zeros.dat', b'\0' * (2 * 1024 * 1024))
with ZipFile(root/'non-elf-binary.zip', 'w') as z:
    z.writestr('runtime/libs/libwrapped.so', b'wrapper payload without ELF magic')
with ZipFile(root/'eligible-non-elf.zip', 'w') as z:
    for name, data in metadata.items(): z.writestr(name, data)
    z.writestr('runtime/libs/libwrapped.so', b'wrapper payload without ELF magic')
    link = ZipInfo('runtime/libs/libwrapped.so.1')
    link.create_system = 3
    link.external_attr = (stat.S_IFLNK | 0o777) << 16
    z.writestr(link, b'libwrapped.so')
with ZipFile(root/'unsafe-symlink.zip', 'w') as z:
    for name, data in metadata.items(): z.writestr(name, data)
    z.writestr('runtime/libs/libwrapped.so', b'wrapper payload without ELF magic')
    link = ZipInfo('runtime/libs/libescape.so.1')
    link.create_system = 3
    link.external_attr = (stat.S_IFLNK | 0o777) << 16
    z.writestr(link, b'../../../../outside')
with ZipFile(root/'duplicate-path.zip', 'w') as z:
    for name, data in metadata.items(): z.writestr(name, data)
    z.writestr('runtime/bin/tool', b'\x7fELF' + b'\0' * 64)
    z.writestr('runtime//bin/tool', b'\x7fELF' + b'\0' * 64)
with ZipFile(root/'empty-runtime.zip', 'w') as z:
    z.writestr('README.txt', b'no runtime payload')
PY

run_rejected() {
  local archive=$1 report=$2
  set +e
  python3 "$ROOT/scripts/audit-runtime-release.py" "$archive" --output "$report"
  local rc=$?
  set -e
  [[ $rc -ne 0 ]]
}

run_rejected "$TMP/unsafe.zip" "$TMP/unsafe.json"
python3 - "$TMP/unsafe.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r['release_eligible'] is False
assert r['elf_files'] == 1
assert 'missing license bundle' in r['blockers']
assert 'missing source provenance' in r['blockers']
PY

run_rejected "$TMP/traversal.zip" "$TMP/traversal.json"
python3 - "$TMP/traversal.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert '../escape' in r['unsafe_paths']
assert 'unsafe archive path detected' in r['blockers']
PY

run_rejected "$TMP/compression-bomb.zip" "$TMP/compression-bomb.json"
python3 - "$TMP/compression-bomb.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r['suspicious_compression']
assert 'unsafe compression ratio detected' in r['blockers']
PY

run_rejected "$TMP/non-elf-binary.zip" "$TMP/non-elf-binary.json"
python3 - "$TMP/non-elf-binary.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r['elf_files'] == 0
assert r['binary_payload_files'] == 1
assert 'missing license bundle' in r['blockers']
assert 'missing source provenance' in r['blockers']
assert 'missing third-party component manifest' in r['blockers']
PY

python3 "$ROOT/scripts/audit-runtime-release.py" \
  "$TMP/eligible-non-elf.zip" --output "$TMP/eligible-non-elf.json"
python3 - "$TMP/eligible-non-elf.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r['release_eligible'] is True
assert r['elf_files'] == 0
assert r['binary_payload_files'] == 2
assert r['blockers'] == []
PY

run_rejected "$TMP/unsafe-symlink.zip" "$TMP/unsafe-symlink.json"
python3 - "$TMP/unsafe-symlink.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r['release_eligible'] is False
assert r['unsafe_symlinks']
assert 'unsafe symlink target detected' in r['blockers']
PY

run_rejected "$TMP/duplicate-path.zip" "$TMP/duplicate-path.json"
python3 - "$TMP/duplicate-path.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r['release_eligible'] is False
assert r['duplicate_entries']
assert 'duplicate archive path detected' in r['blockers']
PY

run_rejected "$TMP/empty-runtime.zip" "$TMP/empty-runtime.json"
python3 - "$TMP/empty-runtime.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r['release_eligible'] is False
assert r['binary_payload_files'] == 0
assert 'no runtime binary payload detected' in r['blockers']
PY

echo 'test-runtime-release-audit: OK'
