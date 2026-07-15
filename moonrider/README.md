# Moonrider

A PortMaster port of Vengeful Guardian: Moonrider (Construct 2 / HTML5) running
on a bundled aarch64 WPE WebKit runtime.

> ⚠️ Tested ONLY on Anbernic RG40xx H / muOS 2508.4 "LOOSE GOOSE".
> Other devices and muOS versions are unverified.

## Controls

The gamepad is forwarded to the game via the HTML5 Gamepad API; the in-game
action of each button is defined by Moonrider and is **not yet confirmed
on-device**. The only mapping the port owns is the quit combo:

| Input                                 | Action             |
|---------------------------------------|--------------------|
| D-Pad / stick / buttons               | In-game (game-defined) |
| L2 + R1, pressed twice within 2 s     | Quit to PortMaster |

The quit combo is a double press (not a hold).

## Assets

No game assets are included. Provide your own legitimate copy — see the top-level
README and `scripts/extract-assets.sh`.

## Credits

Game © JoyMasher / The Arcade Crew / Asteristic Game Studio. Port code Apache 2.0.
Thanks to the PortMaster community.
