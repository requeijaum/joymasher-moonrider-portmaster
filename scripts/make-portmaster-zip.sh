#!/bin/bash
# Build the PortMaster/HarbourMaster zip from build_zip.json.
# Produces Moonrider.zip at the repo root, ready to drop into
# /roms/ports (or install via PortMaster).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="Moonrider.zip"
rm -f "$OUT"

echo "Packaging $OUT ..."

# NOTE: The canonical PortMaster build uses their harbourmaster/build_zip tooling
# which reads build_zip.json. This is a minimal standalone equivalent.
zip -r "$OUT" \
    Moonrider.sh \
    moonrider \
    -x 'moonrider/game/*' \
    -x 'moonrider/log.txt' \
    -x 'moonrider/.xdg/*' \
    -x '*__pycache__*'

echo "Built $OUT"
unzip -l "$OUT" | tail -5
