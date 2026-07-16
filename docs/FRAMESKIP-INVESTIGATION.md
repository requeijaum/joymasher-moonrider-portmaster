# Fixed and Adjustable Frameskip Investigation

Status: design validated in the desktop Construct 2 runtime; device validation is still required.

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

## Proposed implementation

Add a port-owned `moonrider/patches/muos_frameskip.js` and inject it at document start with the existing launcher user-script mechanism.

The shim should:

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

A fixed mode can use the same hook with a launcher-provided override. Suggested precedence:

1. `MOONRIDER_FRAMESKIP` launcher override, when explicitly set;
2. native menu value (`settings_screenmode`);
3. default `OFF`.

The fixed device experiment should start with `MOONRIDER_FRAMESKIP=1`. Once frame pacing, audio synchronization, menus, transitions, and safe quit pass on-device, enable native-menu adjustment and remove the override.

## Important implementation details

Do not throttle `requestAnimationFrame`. The Android settings prototype does this for its FPS cap, but that reduces the frequency of Construct 2 logic and input updates. Render-only suppression is the safer mechanism for this port.

Do not clear a pending redraw permanently. A skipped `drawGL()`/`draw()` call must restore `redraw=true` before returning.

Count actual draws separately from `runtime.fps`. Construct 2 increments `framecount` per logic tick, so its built-in `SHOW FPS` remains a logic-FPS counter under frameskip. Diagnostics should report both logic FPS and presented frames.

Apply the hook only after loading completes. Loader and first-frame behavior should remain untouched.

Reset the cadence phase when the setting changes or a layout changes. This guarantees that the next tick draws immediately and prevents a stale frame during transitions.

## Risks and required device tests

1. **Frame pacing:** verify stable 30/20/15 presentation rather than uneven bursts.
2. **GPU savings:** compare CPU/GPU load and gameplay FPS with OFF and 1.
3. **Audio synchronization:** test music intros/loops, SFX, pause/resume, and cutscenes.
4. **Input latency:** compare attack, jump, parry, and menu navigation at OFF and 1.
5. **Transitions:** test title, stage load, pause, death, checkpoint, and cutscene transitions.
6. **Animated shaders:** verify CRT and time-based shader effects with skipped draws.
7. **Persistence:** change the menu value, quit safely, relaunch, and verify restoration.
8. **Safe quit:** confirm the MODE-button exit path remains unchanged.
9. **Diagnostics:** ensure logs expose active skip, logic ticks, draws, and skipped draws.

## Recommendation

Implement the port-owned shim in two gates:

1. fixed `frameskip=1`, enabled only for a physical regression run;
2. native-menu adjustment after the fixed mode passes.

This is preferable to an FPS cap because it directly removes expensive render work while retaining the game's 60 Hz simulation.
