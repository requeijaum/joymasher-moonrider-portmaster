# Third-party notices

This repository contains source code and build glue for a fan-made PortMaster port. The Apache-2.0 license in `LICENSE` applies only to original port code and documentation. It does not replace the licenses of third-party components.

No commercial game assets are included or licensed by this project. *Vengeful Guardian: Moonrider*, its Construct 2 export, data, artwork, music, sound, video and trademarks remain property of their respective owners.

## Source included in this repository

| Component | Use | License |
|---|---|---|
| miniaudio 0.11.25 | Native audio mixer | Public domain or MIT No Attribution (MIT-0), at the recipient's option |

The complete miniaudio license text is retained at the end of `native/audio-mixer/miniaudio.h`.

## Project-built artifact included in source previews

`runtime-fixes/libGL.so.1` is a small aarch64 no-op GLX stub built from the
versioned original source `runtime-fixes/libgl-stub.c` by
`scripts/build-launcher-backend.sh`. It is part of the PLAYABLE-V2 reproducibility
contract and is covered by this project's Apache-2.0 license. It is **not** the
third-party WPE runtime and contains no commercial game code or assets.

## Components expected in a binary runtime artifact

A binary PortMaster runtime may contain the following independently licensed projects. Exact versions and files must be recorded in the release's generated component manifest before publication.

| Component | Typical license | Upstream |
|---|---|---|
| WPE WebKit / WebKit | LGPL-2.1-or-later and BSD-style licenses, file-dependent | https://wpewebkit.org/ |
| libwpe | BSD-2-Clause | https://github.com/WebPlatformForEmbedded/libwpe |
| WPEBackend-fdo and backend support code | BSD-2-Clause | https://github.com/Igalia/WPEBackend-fdo |
| GStreamer core and plugins | LGPL-2.1-or-later for core and many plugins; plugin-specific exceptions may apply | https://gstreamer.freedesktop.org/ |
| GLib | LGPL-2.1-or-later | https://gitlab.gnome.org/GNOME/glib |
| ICU | Unicode-3.0 | https://icu.unicode.org/ |
| libepoxy | MIT | https://github.com/anholt/libepoxy |
| Wayland | MIT | https://gitlab.freedesktop.org/wayland/wayland |
| libdrm | MIT | https://gitlab.freedesktop.org/mesa/drm |
| ALSA libraries | LGPL-2.1-or-later | https://www.alsa-project.org/ |
| libogg | BSD-3-Clause | https://xiph.org/ogg/ |
| libvorbis | BSD-3-Clause | https://xiph.org/vorbis/ |
| OpenJPEG | BSD-2-Clause | https://www.openjpeg.org/ |
| mpg123 | LGPL-2.1-or-later | https://www.mpg123.de/ |

## Binary release policy

A runtime ZIP must not be published merely because a local build runs. Before upload, the release process must:

1. generate a complete file/hash/component manifest;
2. reject proprietary game assets;
3. identify every shared library and GStreamer plugin, including its originating plugin set and build flags;
4. reject GPL-enabled FFmpeg/GStreamer builds and classify H.264/AAC/MP4 patent exposure;
5. include all required license and notice texts;
6. publish corresponding exact source archives, patches and build provenance for copyleft components;
7. confirm that LGPL dependencies remain dynamically linked and relinkable;
8. reject components whose redistribution terms have not been classified.

Until those gates pass, GitHub releases are source/BYO previews and do not include the WPE binary runtime.
