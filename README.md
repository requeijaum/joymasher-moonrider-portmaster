# Moonrider — PortMaster

<p align="center">
  <em>All rights reserved to JoyMasher, The Arcade Crew and Asteristic Game Studio.</em>
</p>

PortMaster port of **Vengeful Guardian: Moonrider** — the Construct 2 / HTML5
build of the game served through a bundled **WPE WebKit** runtime and rendered
straight to the framebuffer via the `mali-fbdev` backend. The gamepad is read
directly from evdev inside the launcher (no gptokeyb); an **L2 + R1 double-press**
quits back to the Ports menu.

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

## Reproduce a playable build

The clean path has three explicit stages and a regression gate:

```bash
# 1. Cross-build custom aarch64 code from the versioned native/ sources.
docker run --rm --platform linux/arm64 \
  -v /tmp/wpe-spike:/work -v "$PWD":/source:ro -w /work \
  wpebuild:cpp bash /source/scripts/build-launcher-backend.sh

# 2. Assemble WPE runtime and apply the versioned muOS layer to BYO assets.
scripts/assemble-runtime-fresh.sh /tmp/wpe-spike moonrider/runtime
scripts/extract-assets.sh /path/to/game/assets

# 3. Refuse known regressions, then package.
scripts/verify-playable-contract.sh moonrider
scripts/make-portmaster-zip.sh
```

The playable contract requires all of these together:
- `runtime/libs/libGL.so.1`: no-op GLX stub that makes libepoxy select EGL;
- a matched PLAYPAIR trio: native launcher + mixer + `muos_audio_ghost.js`;
- GStreamer plugin paths restricted to `runtime/gst-plugins` (never `libs`);
- `SAFE_QUIT` frontend teardown before taking `/dev/fb0`.

`extract-assets.sh` copies legitimate game assets into `moonrider/game/` and
then deterministically injects the versioned gamepad/audio shims before
`c2runtime.js`. Original assets remain untracked and are never redistributed.

> The intro video `asteristic_logo.mp4` is **mandatory** — without it the engine
> waits forever before the menu (it's also what unlocks WebView audio).

## Install

Drop `Moonrider.zip` into PortMaster (or its `autoinstall/` folder), or unzip it
manually into `/roms/ports`. Then launch **Moonrider** from the Ports menu.

```bash
# on-device, over SSH
scripts/deploy.sh 192.168.1.116
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

The original game assets remain bring-your-own and untracked. The build adds only
the versioned compatibility layer (`muos_gamepad_shim.js`, PLAYPAIR audio ghost,
and generated script tags in `index.html`). Saves live in WebKit local storage.

The gamepad is read straight from evdev inside `moonrider-launch` (no gptokeyb).
The mapping and the **L2 + R1** quit combo live in the canonical sources under
`native/backend/`.

### Controls

The launcher forwards the physical gamepad to the game via the HTML5 Gamepad
API; the in-game action of each button is defined by Moonrider itself and is
**not yet confirmed on-device** for this port. The one mapping we *do* own is the
system quit combo, implemented in the launcher:

| Input                        | Action                          |
|------------------------------|---------------------------------|
| D-Pad / left stick           | In-game movement (game-defined) |
| Face / shoulder buttons      | In-game actions (game-defined)  |
| **L2 + R1, pressed twice within 2 s** | Quit to PortMaster    |

> The quit combo is a **double press** (press, release, press again inside 2 s) —
> holding it once does not trigger. It lives in `backend/exit_combo.h` +
> `backend/moonrider-launch.c` (`btn[6]`=L2, `btn[5]`=R1). Fill in the game's real
> button→action rows here once verified on the device.

## About the assets

The game ships on Steam (AppID 1942010) and GOG as a native Windows build, but
underneath it's the same Construct 2 app this port wraps — which is why serving
those assets through WPE WebKit works. Ten languages, released 12 Jan 2023.

No assets are redistributed here. `moonrider/game/` is bring-your-own and
gitignored; only port code and runtime glue are committed.

## Release status

1. **PLAYABLE-V2 baseline — complete:** reproducible WPE/EGL runtime, libGL stub,
   matched PLAYPAIR trio, native gamepad, and safe frontend lifecycle.
2. **Continuous-SFX fix — complete:** C2 `Audio:Is tag playing` now mirrors native
   voice state. This prevents `mrrun` and `bikemotor_loop` from retriggering every
   tick while preserving the game's explicit one-shot behavior.
3. **Release hardening — complete for RG40xx H/muOS:** clean build, real-device
   smoke test, BYO-only ZIP, checksum, rollback backup, and frontend restoration.
4. **Wider targets** *(future)* — other devices and firmware remain unverified.

### Required game export

Use the desktop/Electron Construct 2 export. The raw Android-derived export is
not compatible with this release and may display its mobile overlay. PLAYABLE-V2
pins the tested core hashes in `manifests/PLAYABLE-V2.json`; the verifier rejects
the known-wrong export before deployment.

## Legal

Port code licensed under **Apache 2.0**. The license covers the port code only.

*Vengeful Guardian: Moonrider* and all its assets (engine, data, audio, sprites,
artwork, icons) are the property of **JoyMasher / The Arcade Crew / Asteristic
Game Studio** and are not included here. Unofficial project, not affiliated with
them.
