# Vengeful Guardian: Moonrider — PortMaster

Unofficial, experimental PortMaster port of **Vengeful Guardian: Moonrider**.
It runs the original desktop Construct 2 export on aarch64 handhelds through
WPE WebKit, with native framebuffer video, gamepad input and audio.

> **Status:** device-verified on Anbernic RG40xx H with muOS 2508.4 LOOSE
> GOOSE. The installable runtime remains a private test build while its public
> redistribution provenance is completed.

## Requirements

- An aarch64 handheld supported by PortMaster.
- A legitimate desktop copy from
  [Steam](https://store.steampowered.com/app/1942010/Vengeful_Guardian_Moonrider/)
  or [GOG](https://www.gog.com/en/game/vengeful_guardian_moonrider).
- The desktop/Electron game export. Android assets are not compatible.

No game assets are included in this repository or in the port package.

## Installation

1. Install an authorized `moonrider.zip` test package through PortMaster.
2. Open `ports/moonrider/` on the active SD card.
3. Create `game/` beside `ASSETS-HERE.txt`.
4. Copy the unchanged contents of the desktop game export into `game/`.
5. Check that `game/index.html`, `game/c2runtime.js`, `game/data.js`,
   `game/images/`, `game/media/` and the intro MP4 are present.
6. Launch **Moonrider** from the Ports menu.

The launcher injects the required gamepad and audio compatibility layers at
runtime. Do not edit `game/index.html`.

## Controls

The port exposes the handheld controls as a standard gamepad. Press
**L2 + R1**, release, then press the same combination again within two seconds
to quit safely.

## Compatibility

Only the **Anbernic RG40xx H / muOS 2508.4 LOOSE GOOSE** combination has been
physically validated. Recorded test sessions ran at roughly 39–46 fps, but
performance varies by scene and other devices are untested.

## More information

- [Technical details, build instructions and release policy](MOREDETAILS.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)
- [Private device-validation report](reports/RELATORIO-SESSAO-20260716.md)

Port by [requeijaum](https://github.com/requeijaum). Vengeful Guardian:
Moonrider and its assets belong to JoyMasher, The Arcade Crew, Asteristic Game
Studio and their respective owners. This project is unofficial.
