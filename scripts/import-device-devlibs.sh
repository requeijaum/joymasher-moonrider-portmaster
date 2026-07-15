#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${HOST:-192.168.1.115}"
SSHPASS="${SSHPASS:-root}"
SSHOPT="-o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=30 -o ServerAliveInterval=5"
DST="$ROOT/audio-mixer/devlibs"
export SSHPASS
mkdir -p "$DST"
for lib in \
  /usr/lib/aarch64-linux-gnu/libasound.so.2 \
  /usr/lib/aarch64-linux-gnu/libogg.so.0 \
  /usr/lib/aarch64-linux-gnu/libvorbis.so.0 \
  /usr/lib/aarch64-linux-gnu/libvorbisfile.so.3 \
  /usr/lib/aarch64-linux-gnu/libvorbisfile.so.3.3.8; do
  sshpass -e scp -O $SSHOPT root@"$HOST":"$lib" "$DST/" 2>/dev/null || true
done
find "$DST" -maxdepth 1 -type f -print -exec sha256sum {} \;
