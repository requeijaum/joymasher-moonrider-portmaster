# Moonrider — PortMaster

Native PortMaster port of **Vengeful Guardian: Moonrider** for aarch64 handhelds.
It runs the game's Construct 2 desktop export through WPE WebKit with a native
framebuffer backend, evdev gamepad input and a native audio mixer.

Tested on **Anbernic RG40xx H / muOS 2508.4 LOOSE GOOSE**. Current performance is
about 23 fps, with lower frame rates and delayed input in heavy scenes.

No game assets are included. You must own the Steam or GOG version.

## Install

An installable release must be named `Moonrider-PortMaster-BYO.zip`. The current
`v0.1.0-alpha.2` release is source-only; do not mistake it for an installable port.
A playable ZIP will be published only when the bundled WPE runtime can be legally
redistributed with its licenses and source provenance.

When an installable ZIP is available:

1. Extract it into `/roms/ports/` or install it through PortMaster.
2. Create `/roms/ports/moonrider/game/`.
3. Copy the **contents** of the desktop/Electron game export into that directory.
4. Confirm these paths exist:

```text
/roms/ports/Moonrider.sh
/roms/ports/moonrider/game/index.html
/roms/ports/moonrider/game/c2runtime.js
/roms/ports/moonrider/game/data.js
/roms/ports/moonrider/game/images/
/roms/ports/moonrider/game/media/
```

The intro `.mp4` from the legitimate desktop export is required. Launch
**Moonrider** from the Ports menu. Use **L2 + R1 twice within two seconds** to quit.

## Port code

- `Moonrider.sh` — PortMaster/muOS launcher and frontend lifecycle
- `native/backend/` — WPE framebuffer backend, launcher and evdev input
- `native/audio-mixer/` — miniaudio/libvorbis mixer
- `shims/` — Construct 2 gamepad and Audio Ghost V12 patches
- `runtime-config/` — WPE runtime environment
- `runtime-fixes/` — EGL-forcing GLX stub
- `scripts/apply-port-layer.py` — injects the patches into BYO assets
- `scripts/make-portmaster-zip.sh` — builds the asset-free installable ZIP

## Build from an approved staging tree

The staging tree must already contain the approved aarch64 WPE runtime:

```text
Moonrider.sh
port.json
moonrider/runtime/
moonrider/ASSETS-HERE.txt
```

Then run:

```bash
STAGING=/path/to/staging \
MOONRIDER_OUT=/tmp/Moonrider-PortMaster-BYO.zip \
  scripts/make-portmaster-zip.sh
```

To prepare your own game directory without modifying the originals:

```bash
MOONRIDER_GAME_DEST=/path/to/staging/moonrider/game \
  scripts/extract-assets.sh /path/to/desktop-game-export
```

## Development history

The full reports, experiments, build logs and rejected approaches are preserved in
the [`research`](https://github.com/requeijaum/joymasher-moonrider-portmaster/tree/research)
branch. `main` is intended to contain only the maintained port and release surface.

## Legal

Port code: [Apache-2.0](LICENSE). Third-party components retain their own licenses;
see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Game code, assets, artwork,
audio, video and trademarks belong to JoyMasher, The Arcade Crew, Asteristic Game
Studio and their respective owners. This is an unofficial project.
