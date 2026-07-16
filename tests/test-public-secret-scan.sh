#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d /tmp/moonrider-secret-scan-test.XXXXXX)
if [[ "${KEEP_TEST_TMP:-0}" = 1 ]]; then
  echo "preserving test directory: $TMP"
else
  trap 'rm -rf "$TMP"' EXIT
fi

printf 'token="%s"\n' 'abc123XYZ' > "$TMP/static-secret.txt"
printf '%s\n' 'dlog("token=" + endedToken + " atual=" + epoch)' > "$TMP/concat.txt"
printf '%s\n' "SSHPASS='<device-password>'" > "$TMP/placeholder.txt"
printf '%s%s\n' '-----BEGIN OPENSSH ' 'PRIVATE KEY-----' > "$TMP/private-key.txt"

if python3 "$ROOT/scripts/scan-public-secrets.py" "$TMP/static-secret.txt"; then
  echo 'static secret was not rejected' >&2
  exit 1
fi
python3 "$ROOT/scripts/scan-public-secrets.py" "$TMP/concat.txt" "$TMP/placeholder.txt"
if python3 "$ROOT/scripts/scan-public-secrets.py" "$TMP/private-key.txt"; then
  echo 'private key marker was not rejected' >&2
  exit 1
fi
python3 "$ROOT/scripts/scan-public-secrets.py"

echo 'test-public-secret-scan: OK'
