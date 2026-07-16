# Fixed and Adjustable Frameskip Investigation

Status: implemented and validated in the desktop Construct 2 runtime and on the RG40xx H.

## Goal

Reduce GPU/render cost without slowing gameplay, audio, input, physics, or the Construct 2 clock. The setting should be adjustable from the game's native Options menu and should not require modifying or redistributing commercial `data.js` assets.

## Findings

### Construct 2 has a safe render-only interception point

In this build, `Runtime.tick()`:

1. schedules the next animation frame;
2. calls `this.logic(raf_time)`;
3. draws only when `this.redraw` is true;
4. calls `drawGL()` or `draw()`.

`tickFunc` calls `self.tick(...)` dynamically, so replacing the runtime instance's `tick` method after startup affects the active loop. Wrapping `drawGL()`/`draw()` can suppress selected draws while all logic ticks continue.

A skipped draw must set `runtime.redraw = true`. This preserves the pending visual update for the next non-skipped tick.

### Proof of concept

A temporary `frameskip=1` hook was injected into the local commercial runtime and removed automatically after four seconds.

- elapsed wall time: 4.001 s
- Construct 2 logic time advanced: 4.016 s
- logic ticks: 241 (~60 Hz)
- rendered frames: 120
- skipped draws: 121
- Construct 2 reported FPS: 60

The result is the desired behavior: logic remains at 60 Hz while presentation is approximately 30 Hz.

### Native Options menu can provide the control

The native menu already contains:

- `SHOW FPS`
- `CRT EFFECT`
- `SCREEN SHAKE`
- `SCREEN MODE`

`SCREEN MODE` is not useful in the fbdev fullscreen port. Its state is stored as `settings_screenmode` in the game's settings Dictionary and cycles through four values. The menu is generated from localization Dictionary entries and runtime SpriteFont objects, so a port-owned shim can change it in memory to:

- label: `FRAME SKIP`
- values: `OFF, 1, 2, 3`
- state: `settings_screenmode` values 0 through 3

This preserves the existing cursor, left/right input, save path, layout, and menu height. It does not patch the commercial `data.js` file on disk.

The original screen-mode actions belong to the Electron plugin. Its `Fullscreen` and `SetWindowSize` actions immediately return when `runningElectron` is false, which is the case under WPE. They therefore have no effect in the port.

## Implemented architecture

The port-owned `moonrider/patches/muos_frameskip.js` is injected at document start with the existing launcher user-script mechanism.

The shim:

1. poll `cr_getC2Runtime()` until the runtime and settings Dictionaries exist;
2. change `menuOPTIONS` from `SCREEN MODE` to `FRAME SKIP`;
3. change `varOptSCREENMODE` to `OFF,1,2,3`;
4. update already-created menu label/value instances, if the menu is open;
5. read and clamp `settings_screenmode` to 0..3;
6. wrap the runtime instance's `tick`, `drawGL`, and `draw` methods exactly once;
7. preserve `redraw=true` after every suppressed draw;
8. expose counters and the active value for device diagnostics.

Recommended cadence:

| Setting | Draw cadence | Target presentation rate at 60 Hz logic |
| --- | --- | --- |
| OFF | every tick | 60 fps |
| 1 | one draw every 2 ticks | 30 fps |
| 2 | one draw every 3 ticks | 20 fps |
| 3 | one draw every 4 ticks | 15 fps |

The fixed diagnostic mode uses the same hook with a launcher-provided override. Precedence is:

1. `MOONRIDER_FRAMESKIP` launcher override, when explicitly set;
2. native menu value (`settings_screenmode`);
3. default `OFF`.

The override is intended for diagnosis. Normal play uses the persisted native-menu
selection; `1` is the recommended starting point on the RG40xx H.

## Important implementation details

Do not throttle `requestAnimationFrame`. The Android settings prototype does this for its FPS cap, but that reduces the frequency of Construct 2 logic and input updates. Render-only suppression is the safer mechanism for this port.

Do not clear a pending redraw permanently. A skipped `drawGL()`/`draw()` call must restore `redraw=true` before returning.

Count actual draws separately from `runtime.fps`. Construct 2 increments `framecount` per logic tick, so its built-in `SHOW FPS` remains a logic-FPS counter under frameskip. Diagnostics should report both logic FPS and presented frames.

Apply the hook only after loading completes. Loader and first-frame behavior should remain untouched.

Reset the cadence phase when the setting changes or a layout changes. This guarantees that the next tick draws immediately and prevents a stale frame during transitions.

## Device validation

The adjustable menu implementation passed a physical RG40xx H smoke session. The
player reported that the setting worked well. The preserved session ran for about
13 minutes 48 seconds and ended through the safe-quit path without a crash.

Telemetry recorded:

- 828 main-loop heartbeats and at least 30,600 presented frames;
- sections near 50–60 presentations/s with frameskip off;
- a long section generally near 30–33 presentations/s with setting `1`;
- return to 50–60 presentations/s near the end;
- 55,907 processed audio commands, zero drops, queue high-water 11/128;
- zero audio stalls and zero circuit-breaker events;
- clean queue drain and audio-worker shutdown.

The WPE log does not mirror the selected menu text, so it cannot independently prove
every short-lived `2`/`3` selection. Automated tests cover the exact 1-in-2, 1-in-3
and 1-in-4 cadences, setting changes, layout changes and late menu discovery.

## Remaining risks

1. Compare input latency and shader appearance during longer sessions at `2` and `3`.
2. Check additional cutscenes and layout transitions for stale-frame artifacts.
3. Keep measuring actual draws separately from Construct 2's logic-FPS counter.
4. Revalidate audio intros and loops whenever either frameskip or Audio Ghost changes.

## Recommendation

Use native-menu setting `1` on the RG40xx H. Keep `OFF` available for comparison and
reserve `MOONRIDER_FRAMESKIP` for fixed diagnostic runs. Do not replace render-only
suppression with an animation-frame cap, because that would also slow simulation and
input.
