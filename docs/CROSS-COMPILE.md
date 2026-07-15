# Cross-compile / runtime provenance

The `moonrider/runtime/` tree is **not hand-assembled** — it is the output of a
Docker build chain that cross-compiles the WPE WebKit stack from x86_64 to
aarch64 for the RG40xxH-class hardware.

## What the runtime contains (target layout)

```
moonrider/runtime/
├── bin/
│   ├── cog                     # WPE launcher browser
│   └── moonrider-launch        # port backend (evdev gamepad + present)
├── lib/
│   ├── libWPEBackend-mali-fbdev.so
│   ├── cog/modules/*.so
│   └── wpe-webkit-1.1/         # WPEWebProcess, WPENetworkProcess, injected-bundle
├── libs/                       # shared .so deps (WPEWebKit, gstreamer, ICU,
│                               #   wayland, epoxy, gbm, soup, krb5, icu, …)
├── gst-plugins/                # GStreamer plugins for OGG/Vorbis/MP4 audio
└── run-moonrider.sh            # invokes cog with the local game/index.html
```

## Build chain (Docker)

The container recipe lives in `docker/` (to be added). Staged like the sibling
project's `docker/original-chain/`:

1. `Dockerfile.1-arm64`  — base aarch64 sysroot + toolchain
2. `Dockerfile.2-epoxy`  — libepoxy / GL glue
3. `Dockerfile.3-cpp`    — WPEWebKit + cog + deps

## Importing the runtime into this repo

The runtime binaries are pulled from the container (and/or from a device's own
system libs) during the **runtime-import** step — this is the moment referenced
as "pegar o código do container e binários/libs auxiliares cross-compiled".

TODO scripts (to port over / re-derive cleanly):
- `scripts/import-runtime-from-container.sh` — copy staged /output out of the image
- `scripts/import-device-devlibs.sh` — pull device-native libs where needed
- `scripts/verify-runtime.sh` — check `file` arch == aarch64 for every .so/bin

> This is a fresh, clean template. The aarch64 runtime is intentionally NOT yet
> committed here — populate it via the import step above. See the sibling
> `moonrider-portmaster-template/runtime/` for a known-good reference set.
