# Cross-compile — build container & runtime provenance

The port has two kinds of native binaries, built two different ways:

1. **The launcher backend** (`moonrider-launch`, `libWPEBackend-mali-fbdev.so`,
   the audio mixer) — *our* C code, cross-compiled aarch64 inside the `wpebuild`
   Docker container. This is what `docker/` reproduces.
2. **The WPE WebKit runtime** (`libWPEWebKit`, GStreamer, ICU,
   wayland, epoxy…) — a large prebuilt aarch64 library set that is **mounted into**
   the container from a prepared engine tree (`/tmp/wpe-spike/engine`); it is
   **not** compiled from apt inside the image.

> The canonical, reproducible recipe lives in [`docker/`](../docker/) — that
> directory is the source of truth. This file explains the flow around it.

## The build container (`wpebuild:cpp`)

Single stage, `linux/arm64` over `debian:bookworm`. On an amd64 host it runs
emulated via binfmt/qemu. It installs only the toolchain + the `-dev` libs the
launcher/mixer actually link against (glib, vorbis, ogg, asound) plus packaging
utils (git, unzip, rsync, file, curl). See `docker/Dockerfile`.

```sh
# one-time: register qemu binfmt so the host can run arm64 images
docker run --privileged --rm tonistiigi/binfmt --install arm64

# build the image
docker buildx build --platform linux/arm64 -t wpebuild:cpp -f docker/Dockerfile .
```

### Historical 3-layer chain (`docker/original-chain/`)

The image was originally three chained layers, preserved for provenance only —
**not** needed to build (the single `Dockerfile` is a correct superset):

```
debian:bookworm-slim
  └─ Dockerfile.1-arm64  : +gcc libglib2.0-dev pkg-config   → wpebuild:arm64
       └─ Dockerfile.2-epoxy : +meson ninja-build           → wpebuild:epoxy
            └─ Dockerfile.3-cpp : +g++                       → wpebuild:cpp
```

> Note: the layer names (`epoxy`, `cpp`) reflect *when* packages were added during
> the original session, not what each layer builds. libepoxy/WPE themselves are
> **not** produced here — they come from the mounted engine tree (below).

## Compiling the launcher backend

The WPE-WebKit headers/libs are **not** from apt — they are bind-mounted from the
prepared engine root (host `/tmp/wpe-spike/engine` → container `/work/engine`):

```sh
docker run --rm \
  -v "$PWD":/work \
  -v /tmp/wpe-spike/engine:/work/engine \
  -w /work \
  wpebuild:cpp bash scripts/build-launcher-backend.sh
```

`build-launcher-backend.sh` compiles, in order:
1. `audio-mixer/muos_audio_mixer.o` — miniaudio + libvorbis (ALSA via `dlopen`)
2. `backend/moonrider-launch` — WPE launcher + evdev gamepad + mixer
3. `backend/libWPEBackend-mali-fbdev.so` — the fbdev/Mali present backend

Outputs land in `backend/`; copy them into the runtime's `bin/` and `lib/`.

## Importing the WPE runtime into the port

The heavy aarch64 runtime is assembled separately and imported wholesale:

- `scripts/import-runtime-from-scratch.sh <src>` — copy a prepared runtime tree
  (`bin/ lib/ libs/ gst-plugins/ run-moonrider.sh`, default src `/tmp/wpe-spike/runtime`)
  into `moonrider/runtime/`.
- `scripts/import-device-devlibs.sh` — pull a handful of device-native `.so`
  (libasound/libogg/libvorbis…) off the RG40xx H over SSH for linking the mixer.

> This repo ships `moonrider/runtime/` as a placeholder. Populate it via the
> import step above. The sibling `moonrider-portmaster-template/runtime/` holds a
> known-good reference set for the RG40xx H / muOS 2508.4 target.

## Reference

Build steps mirror the `electron-construct-arm64-port` skill. Tested target:
Anbernic RG40xx H / muOS 2508.4 "LOOSE GOOSE" (H700, Mali-G31, kernel 4.9.170).

See [`REBUILD-PROVENANCE.md`](REBUILD-PROVENANCE.md) for the actual from-scratch
rebuild log (2026-07-15), verified toolchain versions, and how to restore the
engine tree from the Livinha pendrive backup before compiling.
