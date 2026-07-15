# Repository layout

```
moonrider-pm/
├── Moonrider.sh          Entry-point launcher listed in the Ports menu.
│                         Sources PortMaster control.txt, stops the muOS frontend
│                         to release /dev/fb0, then runs the game through
│                         runtime/run-moonrider.sh. Single-instance lock; restores
│                         the frontend on exit.
├── build_zip.json        HarbourMaster manifest — what goes into Moonrider.zip.
├── port.json             PortMaster port metadata (title, porter, reqs, arch).
├── .gitignore            Excludes game assets, build zips, runtime scratch.
├── README.md             Top-level: controls, build, provenance, legal.
│
├── moonrider/            Becomes /roms/ports/moonrider on the device.
│   ├── README.md         Bundled copy (controls + credits).
│   ├── game/             YOUR extracted C2/HTML5 assets. GITIGNORED.
│   ├── runtime/          Bundled aarch64 WPE runtime: moonrider-launch,
│   │                     libWPEBackend-mali-fbdev.so, WPE/GStreamer/ICU libs,
│   │                     run-moonrider.sh. (import step — see CROSS-COMPILE.md)
│   └── libs/             Extra port-specific shared libs.
│
├── docker/               Reproducible cross-compile container (wpebuild:cpp).
│   ├── Dockerfile        Canonical single-stage arm64 image.
│   ├── README.md         How to build the image + compile the launcher.
│   └── original-chain/   Historical 3-layer provenance (not needed to build).
│
├── scripts/
│   ├── extract-assets.sh          Pull game assets from a legit copy into game/.
│   ├── make-portmaster-zip.sh     Build Moonrider.zip.
│   ├── build-launcher-backend.sh  Cross-compile moonrider-launch + backend + mixer
│   │                              (runs inside wpebuild:cpp).
│   └── deploy.sh                  rsync the port to a device for testing.
│
└── docs/
    ├── STRUCTURE.md      This file.
    └── CROSS-COMPILE.md  Build container + runtime provenance.
```

## Design decisions

- **WPE WebKit, not Android WebView.** The `moonrider-android` project wraps the
  same C2 build in an Android WebView APK. This port targets bare Linux handhelds
  (muOS / PortMaster), so it bundles a native WPE runtime rendering through the
  `mali-fbdev` backend straight to the framebuffer.

- **No cog, no gptokeyb.** Presentation is done by our own `moonrider-launch`
  binary (not the `cog` browser); input is read directly from evdev inside that
  binary (not gptokeyb). The L2+R1 quit combo lives in `backend/exit_combo.h`.

- **No assets in git.** Only port code + runtime. `moonrider/game/` is
  bring-your-own and gitignored.

- **Runtime is built, then imported.** The launcher/backend/mixer are cross-
  compiled in `wpebuild:cpp` (see `docker/`); the heavy WPE library set is
  imported wholesale from a prepared engine tree. See CROSS-COMPILE.md.

## Next steps (populate order)

1. `scripts/extract-assets.sh <copy>` → fill `moonrider/game/`.
2. Build the launcher backend in `wpebuild:cpp` (`scripts/build-launcher-backend.sh`).
3. Import runtime → fill `moonrider/runtime/` (WPE libs + built binaries).
4. Verify the evdev mapping / exit combo in `moonrider-launch`.
5. `scripts/make-portmaster-zip.sh` → test on device via `scripts/deploy.sh`.
