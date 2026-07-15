# Bundled aarch64 WPE runtime goes here.
#
# Populated by the runtime-import step (see docs/CROSS-COMPILE.md), NOT by hand.
# Expected subtree once imported:
#
#   bin/moonrider-launch          our WPE launcher (cross-compiled in wpebuild:cpp)
#   lib/libWPEBackend-mali-fbdev.so   fbdev/Mali present backend (our build)
#   lib/glx-stub.so               legacy GLX shim
#   lib/wpe-webkit-1.1/           WPEWebProcess, WPENetworkProcess, injected-bundle
#   libs/*.so                     WPEWebKit, GStreamer, ICU, wayland, epoxy, gbm, ...
#   gst-plugins/*.so              GStreamer plugins for OGG/Vorbis/MP4 audio
#   run-moonrider.sh              sets LD_LIBRARY_PATH / WPE_BACKEND, execs launcher
#
# NOTE: this port does NOT use cog — presentation is done by moonrider-launch.
# Keeping this placeholder so git tracks the empty runtime/ directory.
