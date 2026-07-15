# Vengeful Guardian: Moonrider — PortMaster

A PortMaster port of **Vengeful Guardian: Moonrider** for aarch64 handhelds.

> ## ⚠️ Tested target
> This port has **only been tested on the Anbernic RG40xx H running muOS 2508.4
> "LOOSE GOOSE"** (H700 SoC, Mali-G31, kernel 4.9.170, aarch64).
>
> It is **not** confirmed working on any other device, muOS version, or PortMaster
> distro (ArkOS, AmberELEC, Knulli, ROCKNIX, etc.). It may work elsewhere given a
> compatible `mali-fbdev` path, but that is unverified — treat other targets as
> experimental and expect breakage.

The game is a Construct 2 / HTML5 title. Rather than an Android WebView (see the
`moonrider-android` sibling project), this port serves the untouched web build
through a bundled **WPE WebKit** runtime cross-compiled x86_64 → aarch64, rendering
straight to the framebuffer via the `mali-fbdev` backend.

## Controls

| Button          | Action              |
|-----------------|---------------------|
| **D-Pad**       | Move                |
| **A**           | Jump                |
| **B**           | Attack              |
| **X / Y**       | Special / Weapon    |
| **L1 / R1**     | Cycle weapon        |
| **Start**       | Pause / Menu        |
| **Select**      | (menu)              |
| **L2 + R1**     | Quit to PortMaster  |

> Final mapping is defined in `moonrider/moonrider.gptk` and the evdev handler in
> the launcher backend. Update this table when the mapping changes.

## What ships in this port

This repo contains **only port code and the runtime** — **no game assets**.
Bring your own legitimate copy of the game (Steam AppID 1942010 / GOG). The
`scripts/extract-assets.sh` helper pulls `c2runtime.js`, `data.js`, `media/`,
`images/`, the `.csv` files and the intro video out of your copy into
`moonrider/game/`.

```
moonrider-pm/
├── Moonrider.sh          # PortMaster launcher (entry point)
├── build_zip.json        # HarbourMaster zip manifest
├── port.json             # PortMaster port metadata
├── moonrider/            # -> becomes /roms/ports/moonrider on device
│   ├── README.md         # bundled copy (controls)
│   ├── moonrider.gptk    # gamepad->key mapping
│   ├── game/             # YOUR extracted game assets (gitignored)
│   ├── runtime/          # bundled aarch64 WPE/cog runtime + libs
│   └── libs/             # extra port libs
├── scripts/              # asset extraction, packaging, deploy
└── docs/                 # build notes, cross-compile chain, patching
```

## Build

```bash
scripts/extract-assets.sh /path/to/game/assets   # populate moonrider/game/
scripts/make-portmaster-zip.sh                   # -> Moonrider.zip
```

## Runtime provenance

The aarch64 runtime under `moonrider/runtime/` (WPE WebKit, cog, GStreamer, ICU,
wayland, mali-fbdev backend) is cross-compiled from a Docker build chain — see
`docs/CROSS-COMPILE.md`. The container recipe and the exact library set are the
"code from the container / cross-compiled binaries" step: they are pulled in
during the runtime-import stage, not hand-copied.

## Legal

Port code licensed under Apache 2.0. *Vengeful Guardian: Moonrider* and all its
assets are property of **JoyMasher / The Arcade Crew / Asteristic Game Studio**
and are **not** included here. Unofficial project, not affiliated.
