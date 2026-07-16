# Runtime directory

Installable packages place the approved aarch64 WPE WebKit runtime here. The
runtime is intentionally absent from Git; source code alone is not playable.

Required release contents:

- `run-moonrider.sh` and the complete aarch64 runtime tree;
- `gst-plugins/*.so` and `lib/glx-stub.so` used by the launcher;
- `RUNTIME-PROVENANCE.md` with exact versions, sources, patches and build flags;
- `LICENSES/` with the applicable third-party notices and license texts;
- `RUNTIME-MANIFEST.sha256`, generated after the tree is final with:

```bash
python3 scripts/generate-runtime-manifest.py /path/to/staging/moonrider/runtime
```

The manifest proves byte-for-byte inventory consistency, not redistribution
permission. The legal/provenance/codec gates in `THIRD_PARTY_NOTICES.md` must
also pass before a binary runtime is published.
