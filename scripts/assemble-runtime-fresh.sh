#!/bin/bash
# assemble-runtime-fresh.sh — rebuild moonrider/runtime/ FROM SCRATCH out of the
# restored WPE engine tree + the freshly cross-compiled launcher binaries.
#
# This is the "fresh" alternative to import-runtime-from-scratch.sh (which copies
# a prepared runtime wholesale). Here we reconstruct the tree from its true
# sources so the provenance of every file is known:
#
#   libs/        <- engine/root .so set (WPEWebKit, GStreamer, ICU, cairo, ...)
#   lib/         <- WPE processes, cog modules, injected bundle (engine) +
#                   glx-stub.so + OUR libWPEBackend-mali-fbdev.so
#   gst-plugins/ <- prepared audio plugin set
#   bin/         <- OUR moonrider-launch (fresh) + cog (engine)
#   run-moonrider.sh <- launcher config (copied from the known-good reference)
#
# registry.bin is NOT shipped: run-moonrider.sh regenerates the GStreamer
# registry in tmpfs on the device at boot.
#
# Usage:
#   scripts/assemble-runtime-fresh.sh [ENGINE_SCRATCH] [DEST]
# Defaults:
#   ENGINE_SCRATCH = /tmp/wpe-spike
#   DEST           = <repo>/moonrider/runtime
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${1:-/tmp/wpe-spike}"
DEST="${2:-$ROOT/moonrider/runtime}"

ENGINE="$SCRATCH/engine/root/usr/lib/aarch64-linux-gnu"
GSTAUDIO="$SCRATCH/gst-plugins-audio"
BACKEND="$SCRATCH/backend"
REF_RUN="$ROOT/../moonrider-portmaster-template/runtime/run-moonrider.sh"

echo "== assemble-runtime-fresh =="
echo "  scratch: $SCRATCH"
echo "  engine : $ENGINE"
echo "  dest   : $DEST"

for d in "$ENGINE" "$GSTAUDIO" "$BACKEND"; do
  [[ -d "$d" ]] || { echo "!! source missing: $d" >&2; exit 1; }
done

# Fresh tree
rm -rf "$DEST"
mkdir -p "$DEST"/{bin,lib/cog/modules,lib/wpe-webkit-1.1/injected-bundle,libs,gst-plugins}

# --- libs/ : flat .so set from engine/root -----------------------------------
echo "-- libs/ (engine .so set) --"
find "$ENGINE" -maxdepth 1 -name '*.so*' -exec cp -a {} "$DEST/libs/" \;
# krb5 / network deps WebKit pulls in, which live outside the flat lib dir
for extra in \
    "$SCRATCH/engine/root/lib/aarch64-linux-gnu/libcom_err.so.2" \
    "$SCRATCH/engine/root/lib/aarch64-linux-gnu/libkeyutils.so.1" \
    "$ENGINE/krb5/plugins/preauth/spake.so"; do
  [[ -e "$extra" ]] && cp -a "$extra"* "$DEST/libs/" 2>/dev/null || true
done

# --- lib/ : WPE processes + cog modules + injected bundle + backends ----------
echo "-- lib/ (WPE processes, cog modules, backends) --"
cp -a "$ENGINE/wpe-webkit-1.1/WPEWebProcess"            "$DEST/lib/wpe-webkit-1.1/"
cp -a "$ENGINE/wpe-webkit-1.1/WPENetworkProcess"        "$DEST/lib/wpe-webkit-1.1/"
cp -a "$ENGINE/wpe-webkit-1.1/libWPEWebInspectorResources.so" "$DEST/lib/wpe-webkit-1.1/" 2>/dev/null || true
cp -a "$ENGINE/wpe-webkit-1.1/injected-bundle/libWPEInjectedBundle.so" "$DEST/lib/wpe-webkit-1.1/injected-bundle/"
cp -a "$ENGINE/cog/modules/"libcogplatform-*.so        "$DEST/lib/cog/modules/"
cp -a "$ENGINE/libWPEBackend-default.so"               "$DEST/lib/" 2>/dev/null || true
# glx-stub: prefer freshly built, fall back to prebuilt in scratch
cp -a "$BACKEND/glx-stub.so"                           "$DEST/lib/" 2>/dev/null || true
# OUR freshly cross-compiled mali-fbdev backend
cp -a "$BACKEND/libWPEBackend-mali-fbdev.so"           "$DEST/lib/"

# --- gst-plugins/ : prepared audio plugin set + core plugins from engine ------
echo "-- gst-plugins/ (audio set + core) --"
cp -a "$GSTAUDIO/"*.so "$DEST/gst-plugins/"
# core elements/tracers live in the engine's gstreamer-1.0 dir, not the audio set
for core in libgstcoreelements.so libgstcoretracers.so; do
  f="$ENGINE/gstreamer-1.0/$core"
  [[ -f "$f" ]] && cp -a "$f" "$DEST/gst-plugins/" || true
done

# --- bin/ : OUR launcher + cog -----------------------------------------------
echo "-- bin/ (fresh moonrider-launch + cog) --"
cp -a "$BACKEND/moonrider-launch"                      "$DEST/bin/"
cp -a "$SCRATCH/engine/root/usr/bin/cog"               "$DEST/bin/" 2>/dev/null || true

# --- run-moonrider.sh : config, from the known-good reference -----------------
echo "-- run-moonrider.sh (from known-good reference) --"
if [[ -f "$REF_RUN" ]]; then
  cp -a "$REF_RUN" "$DEST/run-moonrider.sh"
  chmod +x "$DEST/run-moonrider.sh"
else
  echo "!! reference run-moonrider.sh not found at $REF_RUN — copy it manually" >&2
fi

echo
echo "== done =="
echo "  bin:         $(find "$DEST/bin" -type f | wc -l) files"
echo "  lib:         $(find "$DEST/lib" -type f | wc -l) files"
echo "  libs:        $(find "$DEST/libs" -type f | wc -l) files"
echo "  gst-plugins: $(find "$DEST/gst-plugins" -type f | wc -l) files"
echo "  run script:  $([[ -f "$DEST/run-moonrider.sh" ]] && echo yes || echo NO)"
echo "  total size:  $(du -sh "$DEST" | cut -f1)"
