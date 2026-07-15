# Rebuild log & provenance — `wpebuild:cpp`

This documents a **from-scratch rebuild** of the cross-compile image, done on
2026-07-15, cross-referenced against the engine backup so the whole chain is
reproducible and auditable.

## What was rebuilt

| Item | Value |
|------|-------|
| Image | `wpebuild:cpp` |
| Image ID | `ffe2c1bfc409` |
| Base | `debian:bookworm` (`--platform=linux/arm64`) |
| Host | x86_64 (kernel 6.19 xanmod), arm64 via qemu-aarch64 binfmt |
| Build time | ~286 s (emulated aarch64 apt install) |
| Size | 680 MB |
| Recipe | `docker/Dockerfile` (canonical single stage) |
| Full log | `docs/build-logs/rebuild-wpebuild-cpp-20260715.log` |

### Build command

```sh
# binfmt was already registered; if not:
docker run --privileged --rm tonistiigi/binfmt --install arm64

docker buildx build --platform linux/arm64 --load \
  -t wpebuild:cpp -f docker/Dockerfile .
```

### Verified toolchain (inside the image, `uname -m` = aarch64)

| Tool | Version |
|------|---------|
| gcc / g++ | Debian 12.2.0-14 (12.2.0) |
| glib-2.0 | 2.74.6 |
| libvorbis | 1.3.7 |
| libogg | 1.3.5 |
| alsa (libasound) | 1.2.8 |

These are the `-dev` packages the launcher/mixer link against. The image is a
correct superset of the historical 3-layer chain (`docker/original-chain/`).

## The engine is NOT in the image — it comes from the backup

The heavy WPE-WebKit aarch64 runtime is **bind-mounted**, never baked into the
image. It was archived on 2026-07-15 before the environment was wiped:

```
/media/rafaelfrequiao/Livinha/Portsmaster/wpe-spike-engine-backup-20260715.zip
  244 MB · 1617 files · 616,419,922 bytes uncompressed · unzip -t OK
```

Key contents (what the launcher build links against):

- `wpe-spike/engine/root/usr/lib/aarch64-linux-gnu/` — WPEWebKit, GStreamer,
  JavaScriptCore, libsoup-3.0 shared objects (1126 entries under `engine/root`)
- `wpe-spike/engine/root/usr/include/{wpe-*,libsoup-3.0}/` — headers
- `wpe-spike/libwpe/libwpe-1.0.so.1.8.0` — libwpe 1.8.0
- `wpe-spike/backend/` (14) — our launcher C sources + a prior
  `libWPEBackend-mali-fbdev.so`
- `wpe-spike/audio-mixer/` (28) — miniaudio + libvorbis mixer sources

## Reproducing a full launcher build from scratch

```sh
# 1. Restore the engine scratch tree from the backup
mkdir -p /tmp
unzip -q "/media/rafaelfrequiao/Livinha/Portsmaster/wpe-spike-engine-backup-20260715.zip" \
  -d /tmp                       # -> /tmp/wpe-spike/engine, /backend, /audio-mixer

# 2. (Re)build the image if needed
docker buildx build --platform linux/arm64 --load \
  -t wpebuild:cpp -f docker/Dockerfile .

# 3. Cross-compile the launcher backend, engine bind-mounted at /work/engine
docker run --rm \
  -v "$PWD":/work \
  -v /tmp/wpe-spike/engine:/work/engine \
  -w /work \
  wpebuild:cpp bash scripts/build-launcher-backend.sh
```

> Step 1 is mandatory: without the restored `engine/`, step 3 fails — the WPE
> headers/libs do not come from apt. The backup zip is the only source of that
> engine tree; keep it safe.

## Status

- [x] `wpebuild:cpp` rebuilt from `docker/Dockerfile`, verified aarch64 + toolchain
- [x] Engine preserved on the Livinha pendrive (backup zip, integrity checked)
- [x] Engine restored to `/tmp/wpe-spike/engine` (from backup, 591 MB, engine/root OK)
- [x] Launcher backend cross-compiled against the restored engine — 2026-07-15
- [x] Runtime assembled FRESH from engine + fresh binaries (`assemble-runtime-fresh.sh`)
- [ ] Runtime tested on the RG40xx H (device boot)

## Fresh runtime assembly (2026-07-15)

`moonrider/runtime/` is **gitignored** (large aarch64 binaries). The on-device
install step assembles it (copies binaries) or verifies it (binaries already in
the port zip). It is rebuilt from true sources by
`scripts/assemble-runtime-fresh.sh`, NOT copied wholesale:

| Subtree | Source | Files |
|---------|--------|-------|
| `libs/` | engine/root flat `.so` + krb5/keyutils/spake | 150 |
| `lib/` | WPE processes, cog modules, injected bundle (engine) + **our** mali-fbdev backend + glx-stub | 9 |
| `gst-plugins/` | prepared audio set + core elements/tracers (engine) | 24 |
| `bin/` | **our** fresh `moonrider-launch` + `cog` (engine) | 2 |
| `run-moonrider.sh` | vendored from `runtime-config/run-moonrider.sh` (config, not a binary) | — |

`registry.bin` is intentionally omitted — `run-moonrider.sh` regenerates the
GStreamer registry in tmpfs on the device.

Validation: assembled in `/tmp/moonrider-runtime-fresh` (350 MB), all NEEDED libs
of `moonrider-launch` + `WPEWebProcess` + the mali-fbdev backend resolve within
the tree (0 unresolved, excluding system/device libs). The `moonrider-launch`
inside the tree is byte-for-byte the freshly built one (707,744 B).

### Backups on the Livinha pendrive (`Portsmaster/`)

| Zip | Size | Contents |
|-----|------|----------|
| `wpe-spike-engine-backup-20260715.zip` | 244 MB | engine + backend + audio-mixer scratch |
| `moonrider-runtime-known-good-20260715.zip` | 105 MB | reference runtime from the old template |
| `moonrider-runtime-fresh-20260715.zip` | 134 MB | the freshly assembled runtime |

## Launcher build result (2026-07-15)

Built inside `wpebuild:cpp` with `/tmp/wpe-spike` mounted as `/work`
(log: `docs/build-logs/launcher-build-20260715.log`):

| Artifact | Size | Type |
|----------|------|------|
| `backend/moonrider-launch` | 692 KB | ELF aarch64 PIE executable |
| `backend/libWPEBackend-mali-fbdev.so` | 71 KB | ELF aarch64 shared object |
| `audio-mixer/muos_audio_mixer.o` | 849 KB | ELF aarch64 relocatable |

`moonrider-launch` NEEDED: `libWPEWebKit-1.1.so.0`, `libwpe-1.0.so.1`,
`libglib-2.0.so.0`, `libgobject-2.0.so.0`, `libvorbisfile.so.3`, `libm`, `libc`
— all satisfied by the imported runtime + device libs. Build reproducible from
the backup + `docker/Dockerfile` with zero manual steps.
