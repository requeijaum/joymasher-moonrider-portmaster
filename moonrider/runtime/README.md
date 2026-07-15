# Bundled aarch64 WPE runtime goes here.
#
# This directory is populated by the runtime-import step (see docs/CROSS-COMPILE.md),
# NOT by hand. Expected subtree once imported:
#
#   bin/{cog,moonrider-launch}
#   lib/{libWPEBackend-mali-fbdev.so, cog/modules/, wpe-webkit-1.1/}
#   libs/*.so   (WPEWebKit, gstreamer, ICU, wayland, epoxy, gbm, ...)
#   gst-plugins/*.so
#   run-moonrider.sh
#
# Keeping this placeholder so git tracks the empty runtime/ directory.
