# Runtime redistribution audit — 2026-07-15

## Decision

**The available WPE runtime ZIP is not eligible for public redistribution and is not the PLAYABLE-V2 runtime.** The v0.1.0 alpha release must therefore remain source/BYO-only.

This is a fail-closed decision. It does not assert that the upstream components are non-redistributable; it records that this particular binary bundle lacks the evidence required to redistribute them responsibly.

## Candidate inventory

Candidate: `moonrider-runtime-fresh-20260715.zip`

- SHA-256: `d8f95175f72d20f9509bd3d8c227db1d6c99294cc01690b2a3b056a95e4128c2`
- regular files: 186
- ELF files: 185
- uncompressed bytes: 365,944,351
- commercial/media payload detected: none
- bundled license/notice files detected: none
- `SOURCE_PROVENANCE.json`: absent
- `THIRD_PARTY_MANIFEST.json`: absent

The machine-readable audit was produced with:

```sh
python3 scripts/audit-runtime-release.py runtime-candidate.zip \
  --output runtime-audit.json
```

The command correctly exited non-zero. Its blockers were:

1. missing license bundle;
2. missing source provenance;
3. missing third-party component manifest.

## Functional mismatch

The candidate also predates the validated PLAYABLE-V2 state:

| Artifact | Candidate MD5 | PLAYABLE-V2 MD5 |
|---|---:|---:|
| `runtime/bin/moonrider-launch` | `3668a49dc9a7bfcba3ca4c6a97964492` | `5fb4cbd47ee802dfb1636f65bd27d41d` |
| `runtime/lib/libWPEBackend-mali-fbdev.so` | `e5c8f7a35c85c7f336d02ed2f97caf77` | `e43e27acee6960a5ac8ee2ca0011dd02` |
| `runtime/run-moonrider.sh` | `63820ff45007eed61b130d9d7dbb6ac9` | canonical source `712d1e3f4a8b81243a58092a4cbf6892` |

It contains `libgstgl-1.0.so` and its symlinks, while the validated device configuration removed `libgstgl` from the active runtime. Its launcher script also includes `libs/` in the GStreamer plugin search path, which violates the current runtime contract.

Publishing this ZIP would therefore regress the solved GLX/render path even apart from licensing concerns.

## Requirements for a future binary runtime release

A new runtime must be assembled from the validated source/build pipeline and must contain:

- exact component names, versions, source revisions and SHA-256 hashes;
- SPDX license identifiers per component;
- complete license and notice texts;
- exact source archives, local patches and build provenance for all LGPL and other copyleft components;
- proof that LGPL libraries remain dynamically linked and relinkable;
- classification of every GStreamer plugin by upstream plugin set and build flags;
- rejection of GPL-enabled FFmpeg/GStreamer builds;
- documented H.264/AAC/MP4 patent assessment or removal of those codecs;
- the PLAYABLE-V2 or newer artifact manifest;
- no commercial game content;
- GStreamer plugins isolated under `gst-plugins/`;
- no active `libgstgl` dependency on the framebuffer/EGL target;
- a clean-device smoke test with video, audio, gamepad and frontend restoration.

Until all requirements pass, releases remain source/BYO previews.
