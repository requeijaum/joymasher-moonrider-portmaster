# Moonrider PortMaster — Technical details

For the short installation guide, see [README.md](README.md).

Native PortMaster port of **Vengeful Guardian: Moonrider** for aarch64 handhelds.
It runs the game's Construct 2 desktop export through WPE WebKit with a native
framebuffer backend, evdev gamepad input and a native audio mixer.

Tested on **Anbernic RG40xx H / muOS 2508.4 LOOSE GOOSE**. Recorded
device-validation sessions ran at roughly 39–46 fps. Performance varies by
scene, and no other hardware/firmware combination has been physically validated.

No game assets are included. You must own the Steam or GOG version.

## Install

An installable release must be named `moonrider.zip`. The
`v0.2.0-rc.1-private` candidate is device-verified but restricted to private
testing because the recovered WPE runtime does not yet have complete public
redistribution provenance. Public source releases must not be mistaken for an
installable port. A public playable ZIP will be published only when the bundled
runtime can be redistributed with its required licenses and corresponding source
provenance.

For authorized private testers, or when a public installable ZIP becomes
available:

1. Install `moonrider.zip` through PortMaster.
2. Open the installed `ports/moonrider/` data folder on the active card (the one
   containing `ASSETS-HERE.txt`) and create `game/` beside that marker.
3. Copy the **unchanged contents** of the desktop/Electron game export into `game/`.
4. Confirm these paths exist:

```text
<active-card>/ports/moonrider/game/index.html
<active-card>/ports/moonrider/game/c2runtime.js
<active-card>/ports/moonrider/game/data.js
<active-card>/ports/moonrider/game/images/
<active-card>/ports/moonrider/game/media/
```

The intro `.mp4` from the legitimate desktop export is required. Launch
**Moonrider** from the Ports menu. Use **L2 + R1 twice within two seconds** to quit.
The WPE launcher injects the maintained gamepad and Audio Ghost patches from
`moonrider/patches/` at document start; do not edit `game/index.html`.

## Port code

- `Moonrider.sh` — PortMaster/muOS launcher and frontend lifecycle
- `native/backend/` — WPE framebuffer backend, launcher and evdev input
- `native/audio-mixer/` — miniaudio/libvorbis mixer
- `moonrider/patches/` — runtime-injected gamepad and Audio Ghost V12 patches
- `runtime-config/` — WPE runtime environment
- `runtime-fixes/` — EGL-forcing GLX stub
- `scripts/extract-assets.sh` — copies a complete game export without modifying it
- `scripts/make-portmaster-zip.sh` — builds the asset-free installable ZIP

## Build from an approved staging tree

The staging tree must already contain the approved aarch64 WPE runtime:

```text
Moonrider.sh
moonrider/port.json
moonrider/gameinfo.xml
moonrider/runtime/
  RUNTIME-PROVENANCE.md
  RUNTIME-MANIFEST.sha256
  LICENSES/
moonrider/patches/
moonrider/ASSETS-HERE.txt
```

After the runtime tree, provenance and license payload are final, generate its
complete inventory and build the ZIP:

```bash
python3 scripts/generate-runtime-manifest.py \
  /path/to/staging/moonrider/runtime
STAGING=/path/to/staging \
MOONRIDER_OUT=/tmp/moonrider.zip \
  scripts/make-portmaster-zip.sh
```

Host prerequisites: Bash, Python 3, `file`, `unzip` and GNU coreutils.
The builder refuses to overwrite existing output and emits:

```text
moonrider.zip
moonrider.zip.sha256
moonrider.zip.manifest.sha256
```

To prepare your own game directory without modifying the originals:

```bash
MOONRIDER_GAME_DEST=/path/to/staging/moonrider/game \
  scripts/extract-assets.sh /path/to/desktop-game-export
```

## Development history

The full reports, experiments, build logs and rejected approaches are preserved in
the [`research`](https://github.com/requeijaum/joymasher-moonrider-portmaster/tree/research)
branch. Maintained branches keep only the port, tests, documentation and release
surface.

## Legal

Port code: [Apache-2.0](LICENSE). Third-party components retain their own licenses;
see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Game code, assets, artwork,
audio, video and trademarks belong to JoyMasher, The Arcade Crew, Asteristic Game
Studio and their respective owners. This is an unofficial project.
