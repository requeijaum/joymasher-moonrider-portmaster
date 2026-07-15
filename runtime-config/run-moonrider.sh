#!/bin/sh
# run-moonrider.sh — Moonrider WPE/fbdev runtime launcher for muOS
HERE="$(cd "$(dirname "$0")" && pwd)"
URL="${1:-file://$HERE/smoke.html}"

# Local WPE/WebKit/runtime libraries first.
export LD_LIBRARY_PATH="$HERE/libs:$HERE/lib:/usr/lib/gl4es:/usr/lib:/lib"
export LIBGL_FB=2
export LIBGL_ES=2
export WEBKIT_GST_DISABLE_GL_SINK=1

# GStreamer plugins bundled with the port. WebKit/GStreamer 1.x on this muOS build
# may honor either the generic or the _1_0-suffixed variables, so set both.
export GST_PLUGIN_PATH="$HERE/gst-plugins:$HERE/libs"
export GST_PLUGIN_SYSTEM_PATH="$HERE/gst-plugins:$HERE/libs"
export GST_PLUGIN_PATH_1_0="$HERE/gst-plugins:$HERE/libs"
export GST_PLUGIN_SYSTEM_PATH_1_0="$HERE/gst-plugins:$HERE/libs"
# Use tmpfs for registry to avoid SD/eMMC wear and space issues
export GST_REGISTRY="/run/moonrider/gst-registry.bin"
export GST_REGISTRY_UPDATE=yes
export GST_REGISTRY_FORK=no
rm -f "$GST_REGISTRY" 2>/dev/null || true

# PipeWire/ALSA socket on muOS.
export XDG_RUNTIME_DIR=/run
export PIPEWIRE_RUNTIME_DIR=/run

# WebKit cache in tmpfs to avoid SD/eMMC wear
export XDG_CACHE_HOME=/run/moonrider/.cache
mkdir -p "$XDG_CACHE_HOME"

# WPE backend loader. libwpe 1.x uses WPE_BACKEND_LIBRARY; keep WPE_BACKEND too.
export WPE_BACKEND="$HERE/lib/libWPEBackend-mali-fbdev.so"
export WPE_BACKEND_LIBRARY="$HERE/lib/libWPEBackend-mali-fbdev.so"

# WebKit spawns WPEWebProcess/WPENetworkProcess as separate executables. libWPEWebKit
# has the build-time libexecdir (/usr/lib/aarch64-linux-gnu/wpe-webkit-1.1) hardcoded,
# so without WEBKIT_EXEC_PATH it looks OUTSIDE the port and the web process never
# spawns -> black screen. Point it at our bundled copy to stay self-contained.
export WEBKIT_EXEC_PATH="$HERE/lib/wpe-webkit-1.1"
export WEBKIT_INJECTED_BUNDLE_PATH="$HERE/lib/wpe-webkit-1.1/injected-bundle"

# Diagnostics while stabilizing; set to 0/empty in final release if log overhead matters.
export MUOS_DEBUG=1

# WebKit sandbox off (kernel 4.9 BSP without suitable namespaces).
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export WEBKIT_FORCE_COMPOSITING_MODE=1
export WEBKIT_FORCE_SANDBOX=0

# Legacy GLX shim; preserve any external LD_PRELOAD.
export LD_PRELOAD="${LD_PRELOAD:+$LD_PRELOAD }$HERE/lib/glx-stub.so"

echo "== run-moonrider: URL=$URL =="
exec "$HERE/bin/moonrider-launch" "$URL" 2>&1
