#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

for script in Moonrider.sh scripts/*.sh runtime-config/*.sh; do
  [ -f "$script" ] || continue
  if head -n 1 "$script" | grep -q 'bash'; then
    bash -n "$script"
  else
    sh -n "$script"
  fi
done

PYTHONPYCACHEPREFIX=/tmp/moonrider-pycache python3 -m py_compile scripts/*.py
node --check shims/muos_audio_ghost.js
node --check shims/muos_gamepad_shim.js
node tests/test-audio-ghost.js
sh tests/test-public-release-contract.sh
bash tests/test-runtime-release-audit.sh
bash tests/test-source-preview-package.sh
bash scripts/verify-playable-contract.sh

git diff --check

echo 'verify-public-release: OK'
