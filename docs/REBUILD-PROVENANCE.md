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
- [ ] Runtime imported into `moonrider/runtime/` and tested on the RG40xx H

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
