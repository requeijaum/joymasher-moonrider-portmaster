# Boss music handoff fix

Date: 2026-07-16
Target: Anbernic RG40xx H, muOS 2508.4 LOOSE GOOSE

## Symptom

During the stage 1 cannon boss, sound effects could continue while the battle music
remained silent. Mixer telemetry from the physical session did not show queue
saturation, voice exhaustion, a decoder failure, a watchdog stall, or a circuit
breaker event.

## Intended Construct 2 behavior

The event sheet starts `genericbossintro` as the `musicINTRO` tag. That file is a
short 330 ms cue. When it ends, the game starts `genericboss` as `musicLOOP` with
looping enabled. The loop file is approximately 42.2 seconds long.

The files are deliberately separate. Treating the intro as the complete boss track
would be incorrect.

## Root cause

The Audio Ghost already converted canonical names such as `stage_1-1_intro` and
`stage_1-1_loop` to an atomic native `PLAYPAIR`. The generic boss names do not use
the `_intro`/`_loop` convention, so `genericbossintro` was sent as a standalone
`PLAY` and depended on a synthetic Construct 2 `Audio.OnEnded` event.

The synthetic event changed `Audio.prototype.cnds.OnEnded` temporarily. Construct 2,
however, resolves object references while loading the project and stores the original
function in each compiled `Condition.func`. Changing only the prototype did not
change that cached reference. The trigger was attempted, its first condition remained
false, and `genericboss` was never requested.

The same bridge is used by the three `OnEnded` dependencies in this project:

- `musicINTRO`, which starts the corresponding music loop;
- `MR_CHIP_PICKUP`, which restores the current music after the pickup cue;
- `elevator_start`, which starts `elevator_loop`.

## Implementation

Audio Ghost V13 makes two changes:

1. It defines explicit native pairs for legacy names that cannot be inferred:
   - `genericbossintro` -> `genericboss`;
   - `genoqueenintro` -> `genoqueenloop`.
2. During a synthetic `OnEnded`, it temporarily replaces both the prototype
   condition and every matching cached `runtime.cndsBySid[*].func` reference. All
   references are restored in a `finally` block before control returns to the game.

The native pair is the reliability path for boss music: the worker schedules the
long loop before the 330 ms intro starts, so JavaScript scheduling delays cannot
create a silent gap. The repaired synthetic event preserves the original event-sheet
semantics for pickups, elevators, and other end-triggered actions.

Existing same-name/same-tag loop suppression prevents the compatibility `OnEnded`
from restarting a loop that `PLAYPAIR` already scheduled.

## Preserved invariants

- The audio worker remains the only owner of miniaudio objects.
- WebKit and the GLib main loop remain enqueue-only.
- Queue capacity, coalescing, two-phase voice retirement, watchdogs, and circuit
  breaker behavior are unchanged.
- No commercial game code or assets are distributed.
- Frameskip remains render-only and does not skip Construct 2 ticks or audio work.

## Automated regression coverage

`tests/test-audio-ghost.js` now models Construct 2's cached `Condition.func` behavior
and verifies:

- `genericbossintro` emits `PLAYPAIR` with `genericboss`;
- `genoqueenintro` emits `PLAYPAIR` with `genoqueenloop`;
- cached conditions accept synthetic `musicINTRO`, `elevator_start`, and
  `MR_CHIP_PICKUP` triggers;
- every patched condition is restored after each trigger;
- existing native `IsTagPlaying` behavior remains intact.

The regression failed against V12 before the production change and passed against
V13. The complete local CI-equivalent suite also passed: JavaScript and shell syntax,
Audio Ghost, frameskip, latest-state gamepad, command queue, worker, lifecycle,
service and mailbox tests, BYO extraction/injection, package structure, manifest
hashes, and public-secret scanning.

The aarch64 cross-build was not repeated in this pass because execution of the
throwaway WPE build container was denied. The audio change itself is JavaScript-only;
the branch's native frameskip launcher had already passed its earlier cross-build.
This limitation is explicit and is not represented as a fresh cross-build result.

## Physical validation pending

No device deployment or physical test was performed for this fix on 2026-07-16.
The next RG40xx H session should:

1. Confirm the log identifies Audio Ghost V13.
2. Enter the stage 1 cannon boss while normal sound effects are active.
3. Verify the short cue transitions immediately to sustained battle music.
4. Remain in the battle for more than 45 seconds and confirm the 42.2-second track
   loops without a gap or restart glitch.
5. Verify attacks and other concurrent sound effects remain audible.
6. Collect a case where a chip pickup finishes and the previous music resumes.
7. Verify an elevator start cue transitions to the continuous elevator loop.
8. If reachable, verify the Geno Queen intro transitions to its loop.
9. Check the log for `MUOS_PLAYPAIR intro=genericbossintro loop=genericboss ms=330`,
   zero dropped audio commands, no decoder errors, no stalls, and no circuit breaker.

If the boss remains silent, preserve the complete log and do not alter the frozen
`v0.2.0-rc.1-private` tag. The next investigation should distinguish a missing
`PLAYPAIR` message from a native pair scheduling or decoder failure.
