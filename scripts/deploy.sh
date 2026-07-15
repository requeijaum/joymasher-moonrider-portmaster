#!/bin/bash
# Deploy the port to a device over rsync/SSH for on-device testing.
# Usage: scripts/deploy.sh [user@host] [/remote/roms/ports]
set -euo pipefail

HOST="${1:-}"
REMOTE_PORTS="${2:-/roms/ports}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "$HOST" ]; then
  echo "Usage: $0 user@host [/remote/roms/ports]" >&2
  exit 1
fi

echo "Deploying to $HOST:$REMOTE_PORTS"
rsync -av --delete \
  --exclude 'log.txt' --exclude '.xdg/' \
  "$ROOT/Moonrider.sh" \
  "$ROOT/moonrider" \
  "$HOST:$REMOTE_PORTS/"

echo "Deployed. Launch 'Moonrider' from the Ports menu on device."
