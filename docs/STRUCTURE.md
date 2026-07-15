# Repository layout

```
moonrider-pm/
├── Moonrider.sh          Entry-point launcher listed in the Ports menu.
│                         Sources PortMaster control.txt, sets up the runtime
│                         env (LD_LIBRARY_PATH, WPE backend, GST plugins),
│                         starts gptokeyb, runs the game, cleans up on exit.
├── build_zip.json        HarbourMaster manifest — what goes into Moonrider.zip.
├── port.json             PortMaster port metadata (title, porter, reqs, arch).
├── .gitignore            Excludes game assets, build zips, runtime scratch.
├── README.md             Top-level: controls, build, provenance, legal.
│
├── moonrider/            Becomes /roms/ports/moonrider on the device.
│   ├── README.md         Bundled copy (controls + credits).
│   ├── moonrider.gptk    gptokeyb pad→key mapping (placeholder, refine).
│   ├── game/             YOUR extracted C2/HTML5 assets. GITIGNORED.
│   ├── runtime/          Bundled aarch64 WPE/cog runtime + libs. (import step)
│   └── libs/             Extra port-specific shared libs.
│
├── scripts/
│   ├── extract-assets.sh       Pull game assets from a legit copy into game/.
│   ├── make-portmaster-zip.sh  Build Moonrider.zip.
│   └── deploy.sh               rsync the port to a device for testing.
│
└── docs/
    ├── STRUCTURE.md      This file.
    └── CROSS-COMPILE.md  Runtime provenance / Docker cross-compile chain.
```

## Design decisions

- **WPE WebKit, not Android WebView.** The `moonrider-android` project wraps the
  same C2 build in an Android WebView APK. This port targets bare Linux handhelds
  (muOS / PortMaster), so it bundles a native WPE runtime rendering through the
  `mali-fbdev` backend straight to the framebuffer.

- **No assets in git.** Only port code + runtime. `moonrider/game/` is
  bring-your-own and gitignored.

- **Runtime is imported, not authored.** The heavy aarch64 `.so` set comes out of
  a cross-compile container — see CROSS-COMPILE.md. This keeps the port code clean
  and separable from the binary runtime.

## Next steps (populate order)

1. `scripts/extract-assets.sh <copy>` → fill `moonrider/game/`.
2. Import runtime → fill `moonrider/runtime/` (Docker chain / device libs).
3. Build the launcher backend (`moonrider-launch`) — evdev gamepad + exit combo.
4. Refine `moonrider.gptk` against the game's real keycodes.
5. `scripts/make-portmaster-zip.sh` → test on device via `scripts/deploy.sh`.
