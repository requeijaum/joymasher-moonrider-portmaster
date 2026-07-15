#!/bin/bash
# Deploy the port to a muOS device over rsync/SSH for on-device testing.
#
# This is a MANUAL install (not PortMaster/HarbourMaster autoinstall) — no zip
# needed. rsync streams the staging tree straight to the device, incrementally
# (resumes only what's missing) and works around the unionfs quirks on muOS.
#
# muOS layout (RG40xx H, 2508.4):
#   launcher -> /mnt/union/ROMS/Ports/Moonrider.sh   (what the Ports menu lists)
#   payload  -> /mnt/union/ports/moonrider/          (runtime/ + game/)
#
# The port payload (runtime + game) is gitignored, so deploy from a populated
# staging tree, not the repo. Assemble it first (assemble-runtime-fresh.sh for
# runtime, extract-assets.sh for game) or point STAGING at an existing one.
#
# Usage:
#   SSHPASS=<devpass> STAGING=/tmp/moonrider-staging scripts/deploy.sh <host>
#
# Env:
#   SSHPASS   device root password (required; muOS default is 'root')
#   STAGING   staging dir containing Moonrider.sh + moonrider/ (default /tmp/moonrider-staging)
#   HOST      device hostname or IP (required unless passed as argument)
set -euo pipefail

HOST="${1:-${HOST:-}}"
STAGING="${STAGING:-/tmp/moonrider-staging}"
PORTS_LAUNCHER="/mnt/union/ROMS/Ports/Moonrider.sh"
PORTS_PAYLOAD="/mnt/union/ports/moonrider"

if [[ -z "${SSHPASS:-}" ]]; then
  echo "Set SSHPASS to the device root password (muOS default: root)." >&2
  exit 2
fi
if [[ -z "$HOST" ]]; then
  echo "Pass the device hostname/IP as argument or set HOST." >&2
  exit 2
fi
if [[ ! -d "$STAGING/moonrider" ]]; then
  echo "Staging tree not found: $STAGING/moonrider" >&2
  echo "Assemble runtime + game into $STAGING first." >&2
  exit 2
fi
export SSHPASS
RSH="sshpass -e ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=15"

# Preserve executable bits and timestamps; avoid chown across unionfs/FAT.
# Staging must be a real tree (release builds do not rely on game symlinks).
RSYNC_OPTS="-rlptD --no-o --no-g --info=progress2"

echo "Deploying payload -> $HOST:$PORTS_PAYLOAD/"
rsync $RSYNC_OPTS -e "$RSH" "$STAGING/moonrider/" "root@$HOST:$PORTS_PAYLOAD/"

echo "Deploying launcher -> $HOST:$PORTS_LAUNCHER"
rsync $RSYNC_OPTS -e "$RSH" "$STAGING/Moonrider.sh" "root@$HOST:$PORTS_LAUNCHER"

echo "Making launcher + binaries executable"
$RSH "root@$HOST" "
  chmod +x '$PORTS_LAUNCHER' \
    '$PORTS_PAYLOAD/runtime/run-moonrider.sh' \
    '$PORTS_PAYLOAD/runtime/bin/'* 2>/dev/null || true
"

echo "Deployed. Launch 'Moonrider' from the Ports menu on the device."
