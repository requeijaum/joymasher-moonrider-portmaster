# PLAYABLE-V2 release report — 2026-07-15

## Result

PLAYABLE-V2 is deployed and automated smoke-tested on RG40xx H / muOS 2508.4.
The desktop/Electron Construct 2 export is restored. WPE/EGL rendering, native
PLAYPAIR audio, evdev gamepad initialization, save loading, clean timeout exit,
and frontend restoration are confirmed by the device log.

## Export incident and recovery

A release staging was initially populated from `/tmp/Moonrider.zip`. That archive
contained the wrong raw Android-derived game export and caused the visible mobile
overlay. It also replaced `index.html`, `c2runtime.js`, and `data.js` on the device.

The native runtime was not corrupted. Its launcher, backend, and libGL-stub hashes
remained identical to the known-good baseline. The correct desktop export was
recovered from:

`/mnt/mmc/moonrider-old-backup-20260715/moonrider/moonrider-game/`

The wrong deployment was preserved without deletion at:

`/mnt/sdcard/ports/moonrider/game-wrong-android-20260715-v2/`

The correct desktop assets are now backed up externally at:

`/path/to/external-backup/Portsmaster/moonrider-game-desktop-known-good-20260715/`

## Pinned desktop-export hashes

- `index.html`: `96339037629d4773b1447521713db0f6`
- `c2runtime.js`: `bf14593130809fa4932e6bb5a8bc76f6`
- `data.js`: `e091a9f090f09f24cebeea8ef3a0154c`

These hashes are now part of `manifests/PLAYABLE-V2.json`. The release verifier
passes the desktop export and deliberately rejects the wrong export.

## Runtime hashes on device

- `runtime/libs/libGL.so.1`: `1115e827437465a2221e0baf8611379e`
- `runtime/bin/moonrider-launch`: `5fb4cbd47ee802dfb1636f65bd27d41d`
- `runtime/lib/libWPEBackend-mali-fbdev.so`: `e43e27acee6960a5ac8ee2ca0011dd02`

## Automated validation

Passed:

- shell syntax checks;
- Python compilation;
- Node audio-ghost regression test;
- canonical source and artifact hashes;
- PLAYPAIR launcher/mixer/ghost contract;
- native `IsTagPlaying` bridge;
- game shim order;
- positive desktop-export contract;
- negative wrong-export contract;
- clean 35-second device smoke test;
- frontend restoration and idle process state;
- BYO ZIP integrity and no proprietary game files.

Observed device signals include `MUOS_AUDIO_GHOST_V12_IPC`,
`MUOS_ACTS_WRAPPED_V12`, `Using XBOX buttons`, successful local save loading,
and a native `PLAYPAIR` command accepted by the mixer.

## Release artifact

`/path/to/external-backup/Portsmaster/releases/Moonrider-PLAYABLE-V2-BYO-correct.zip`

SHA-256:

`0ddec7aae0ba9b0206ba00f820adb1420f4847cf64d1c30fb94b7b1b00c9064d`

This archive is BYO-only and does not redistribute proprietary game assets.
