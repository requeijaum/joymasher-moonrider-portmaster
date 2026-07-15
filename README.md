# Moonrider — PortMaster

<p align="center">
  <em>All rights reserved to JoyMasher, The Arcade Crew and Asteristic Game Studio.</em>
</p>

PortMaster port of **Vengeful Guardian: Moonrider** — the Construct 2 / HTML5
build of the game served through a bundled **WPE WebKit** runtime and rendered
straight to the framebuffer via the `mali-fbdev` backend. The gamepad is read
directly from evdev inside the launcher (no gptokeyb); an **L2 + R1** combo quits
back to the Ports menu.

This repo contains **only the port code and runtime glue**. No game assets are
included — bring your own copy of the game (see below).

> ## ⚠️ Tested target
> Only tested on the **Anbernic RG40xx H running muOS 2508.4 "LOOSE GOOSE"**
> (H700 SoC, Mali-G31, kernel 4.9.170, aarch64). Other devices, muOS versions and
> PortMaster distros (ArkOS, AmberELEC, Knulli, ROCKNIX…) are **unverified** —
> treat them as experimental and expect breakage.

## Requirements

- A PortMaster-capable aarch64 handheld (tested: RG40xx H / muOS 2508.4)
- A legitimate copy of the game's assets
- The bundled aarch64 WPE runtime under `moonrider/runtime/` (imported
  separately — see [`docs/CROSS-COMPILE.md`](docs/CROSS-COMPILE.md))

## Build

```bash
scripts/extract-assets.sh /path/to/game/assets   # populate moonrider/game/
scripts/make-portmaster-zip.sh                   # -> Moonrider.zip
```

`extract-assets.sh` copies your game assets into `moonrider/game/`; the packager
then assembles the HarbourMaster zip described by `build_zip.json`. To stage off a
full SSD, both scripts honor env overrides (symlink mode + `/tmp` output):

```bash
MOONRIDER_LINK=1 MOONRIDER_GAME_DEST=/tmp/stage/game \
  scripts/extract-assets.sh /path/to/game/assets
MOONRIDER_OUT=/tmp/Moonrider.zip MOONRIDER_INCLUDE_GAME=1 \
  scripts/make-portmaster-zip.sh
```

The "game assets folder" is the one holding `c2runtime.js`, `data.js`, `media/`,
`images/`, the `.csv` files and `asteristic_logo.mp4`.

> The intro video `asteristic_logo.mp4` is **mandatory** — without it the engine
> waits forever before the menu (it's also what unlocks WebView audio).

## Install

Drop `Moonrider.zip` into PortMaster (or its `autoinstall/` folder), or unzip it
manually into `/roms/ports`. Then launch **Moonrider** from the Ports menu.

```bash
# on-device, over SSH
scripts/deploy.sh root@192.168.1.115 /roms/ports
```

## The port

Rather than an Android WebView (see the sibling `moonrider-android` project),
this port ships a native **WPE WebKit** runtime cross-compiled x86_64 →
aarch64 and renders through `mali-fbdev`:

- `Moonrider.sh` — launcher: sources PortMaster `control.txt`, stops the muOS
  frontend to release `/dev/fb0`, then runs the game via `runtime/run-moonrider.sh`
- `moonrider/runtime/` — the bundled aarch64 WPE/GStreamer/ICU library set plus
  our `moonrider-launch` binary and `libWPEBackend-mali-fbdev.so`
  (built via `docker/` + imported — see `docs/CROSS-COMPILE.md`)

Everything under `moonrider/game/` (`c2runtime.js`, `data.js`, sprites, audio) is
the untouched original. Saves live in the WebKit local storage.

The gamepad is read straight from evdev inside `moonrider-launch` (no gptokeyb).
The mapping and the **L2 + R1** quit combo live in the launcher C source
(`backend/evdev_gamepad.c`, `backend/exit_combo.h`).

### Controls

| Button      | Action              |
|-------------|---------------------|
| **D-Pad**   | Move                |
| **A**       | Jump                |
| **B**       | Attack              |
| **X / Y**   | Special / Weapon    |
| **L1 / R1** | Cycle weapon        |
| **Start**   | Pause / Menu        |
| **L2 + R1** | Quit to PortMaster  |

The mapping lives in the launcher C source; update this table when it changes.

## About the assets

The game ships on Steam (AppID 1942010) and GOG as a native Windows build, but
underneath it's the same Construct 2 app this port wraps — which is why serving
those assets through WPE WebKit works. Ten languages, released 12 Jan 2023.

No assets are redistributed here. `moonrider/game/` is bring-your-own and
gitignored; only port code and runtime glue are committed.

## Roadmap

1. **Import the runtime** — populate `moonrider/runtime/` from the cross-compile
   container (`docs/CROSS-COMPILE.md`); the repo currently ships only a placeholder.
2. **On-device bring-up** — first boot on the RG40xx H, read `log.txt`, tune the
   WPE/`mali-fbdev` env until the game presents.
3. **Gamepad mapping** — verify the evdev mapping in `moonrider-launch` against
   the game's real keycodes; confirm the exit combo (L2+R1).
4. **Performance** — measure FPS in real gameplay (moving scene, not a static one).
5. **Wider targets** *(maybe)* — validate on other muOS versions / PortMaster
   distros once the RG40xx H path is solid.

## Legal

Port code licensed under **Apache 2.0**. The license covers the port code only.

*Vengeful Guardian: Moonrider* and all its assets (engine, data, audio, sprites,
artwork, icons) are the property of **JoyMasher / The Arcade Crew / Asteristic
Game Studio** and are not included here. Unofficial project, not affiliated with
them.
