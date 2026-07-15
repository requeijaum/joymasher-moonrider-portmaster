# WPE cache-locality investigation — Moonrider / RG40xx H

Date: 2026-07-15

## Why this belongs in this project

This report applies Mike Acton's CppCon 2014 talk, **“Data-Oriented Design and C++”**, to the Moonrider WPE port. It extends the PLAYABLE-V2 baseline documented in `reports/RELATORIO-PLAYABLE-V2-RELEASE-20260715.md`; it does not replace that known-good runtime.

Source video: <https://youtu.be/rX0ItVEVjHc>

## Executive conclusion

There is a real optimization opportunity, but **“enable CPU cache” is not a switch**. The H700 already uses its hardware caches automatically. The actionable goal is to reduce cache-line waste, pointer chasing, CPU migration, and unnecessary wakeups in measured hot paths.

The dominant target is almost certainly `WPEWebProcess` / JavaScriptCore / Construct 2, not the small fbdev backend. The current WPE WebKit 2.38.6 runtime is a stripped imported binary; its original CPU tuning flags are unknown. Our build container recompiles only the launcher, mixer, backend, and GL stub.

Recommended sequence:

1. Measure PMU/cache behavior on the PLAYABLE-V2 binary.
2. Build an A/B native runtime with Cortex-A53 tuning.
3. Only if `WPEWebProcess` is cache-miss bound, rebuild the exact WPE 2.38.6 source with controlled flags.
4. Profile Construct 2 hot loops before attempting data-layout changes.
5. Keep every optimization behind rollback and compare against PLAYABLE-V2.

## What the video actually says

The useful claims are about data movement, not compiler folklore:

- `00:14:22`: latency and throughput differ in parallel systems; reason from measured data.
- `00:29:48`: historical comparison used in the talk: register access is effectively free, L1 roughly 3 cycles, L2 roughly 20, and DRAM 200+ cycles. These are illustrative PS4/x64-era numbers, not H700 measurements.
- `00:31:24`: L2 misses often dominate execution time; arithmetic can be a minority of the cost.
- `00:34:23`: the example spends about ten times more time waiting on misses than performing useful arithmetic.
- `00:36:12`: cache misses should be budgeted per frame.
- `00:36:54`: an example cache line carries about 90% unused data; layout determines useful bandwidth.
- `01:14:00`: use a profiler to inspect misses for a function and transformation, not assumptions.
- `01:26:37`: the speaker did not treat LTO/PGO as substitutes for good data layout.

Core principle: organize data around the transformation performed each frame. Contiguous, minimal hot data generally beats object graphs and generic abstractions.

## Current Moonrider runtime facts

### WPE engine

- WPE WebKit: **2.38.6** (`wpe-webkit-1.1.pc` and `WebKitVersion.h`).
- libwpe: 1.14.0 in the engine sysroot.
- `WPEWebProcess` and `libWPEWebKit-1.1.so.0.2.9` are stripped aarch64 binaries.
- The ELF files expose build IDs but no `.comment` section identifying compiler flags.
- The engine is restored from backup; `docker/Dockerfile` does not build WebKit.

Therefore, adding `-mcpu=cortex-a53` to `scripts/build-launcher-backend.sh` does **not** optimize JavaScriptCore or WebCore.

### Native backend

`native/backend/backend-mali-fbdev.c` is not a meaningful cache target:

- only a few tiny state structures;
- no per-frame pixel copies;
- no large traversal;
- frame callbacks increment counters and dispatch completion;
- synchronous per-frame logging is already disabled.

Its hot-path footprint should fit comfortably in L1.

### Input

`native/backend/evdev_gamepad.c` uses compact arrays and a small snapshot. Its data already has good locality. The inefficiency is elsewhere:

- scans every input fd;
- wakes every 1 ms with `usleep(1000)`;
- locks the pad state for each event;
- the GLib side locks and copies the snapshot at 60 Hz even when unchanged.

Replacing busy polling with blocking `poll()`/`epoll()` can reduce CPU wakeups and battery use. This is a scheduler/wakeup optimization more than a cache-layout optimization.

### Audio mixer

`muos_audio_mixer.c` contains the clearest textbook data-oriented issue:

```c
muos_voice voices[64];
```

Each `muos_voice` embeds a large `ma_sound`. `find_voice()`, `alloc_voice()`, reaping, and pair-slot checks linearly scan that array while touching metadata separated by the large object stride. A structure-of-arrays metadata index or compact active-slot list would improve locality.

However, these scans run on audio commands or the 1 Hz reap timer, not per audio sample. They are unlikely to affect frame rate. Optimize only if profiling disproves that assessment.

### Construct 2 / JavaScriptCore

This is the likely dominant CPU/cache domain:

- Construct 2 traverses many JavaScript objects every tick;
- object properties, instance arrays, behaviors, collision structures, and JSC GC metadata can cause pointer chasing;
- WebGL command generation also runs in the WebProcess;
- changing generated `c2runtime.js` blindly is high risk and may destabilize saves, timing, collisions, or rendering.

Typed arrays or hot/cold splits could help only after identifying a specific high-cost loop and preserving semantics.

## Ranked experiments

### P0 — establish a cache baseline

Capture a fixed 60-second gameplay segment on PLAYABLE-V2:

- frame/time behavior;
- `cycles`, `instructions`, IPC;
- `cache-references`, `cache-misses`;
- L1 data-cache refill/miss events;
- L2 data-cache refill events;
- branch misses;
- context switches and CPU migrations;
- per-thread CPU and RSS/PSS;
- CPU frequency and thermal state.

Use the WebProcess PID, not only the launcher PID. Check `perf list` first because muOS may expose ARM PMUv3 events under different names. If symbolic events are absent, Cortex-A53 PMU raw events can be tested only after confirming kernel support.

Run the same scene at least three times after one warm-up. Save raw output with runtime hashes and exact timestamps.

### P1 — tune code we actually build

Create a separate A/B build, never overwrite PLAYABLE-V2:

- retain `-O2` baseline;
- test `-O3 -mcpu=cortex-a53 -mtune=cortex-a53` for launcher/mixer/backend;
- inspect generated ELF architecture and dependencies;
- avoid `-ffast-math` because it can alter audio and game-visible numerical behavior;
- do not assume LTO helps; measure binary size, startup, audio CPU, and frame behavior.

Expected impact: small overall, potentially measurable in miniaudio decode/resampling. The backend itself should not move the needle.

### P2 — replace evdev busy polling

Use blocking `poll()` over all input fds with a bounded timeout for shutdown. Batch all available events before one lock/update. This should reduce idle CPU and wakeups without changing WPE.

Acceptance gates:

- no added input latency;
- analog and D-pad mappings unchanged;
- exit combo unchanged;
- lower context switches/wakeups;
- no lifecycle regression.

### P3 — test CPU affinity, do not assume it

The Cortex-A53 cores have private L1 caches and a shared higher-level cache. CPU migration can discard warm private-cache state, but pinning a multi-threaded WebProcess too aggressively can reduce throughput.

Compare:

- scheduler default;
- stable WebProcess affinity to a measured subset of cores;
- launcher/audio on another core only if thread-level data supports it.

Reject affinity if it worsens frame pacing, audio, thermal behavior, or total misses.

### P4 — rebuild exact WPE WebKit 2.38.6

This is the only way to apply Cortex-A53 code generation to WebCore/JSC itself. Requirements:

- obtain and pin exact 2.38.6 source and dependency versions;
- preserve the same WPE ABI and runtime feature set;
- record all CMake flags;
- build generic and Cortex-A53 variants from the same source;
- validate JIT tier availability and executable-memory policy;
- compare PMU data and gameplay, not just startup time.

This is a large build and needs external-backup storage; it must not consume the nearly-full SD card. A newer WPE/JSC may produce larger gains than retuning 2.38.6, but introduces substantially greater rendering, ABI, and game-compatibility risk.

### P5 — surgical Construct 2 layout work

Only after profiling identifies a stable hot loop:

- instrument loop counts and time;
- identify which fields are read each frame;
- split hot scalar data from cold object metadata where feasible;
- prefer contiguous typed arrays for homogeneous numeric data;
- process in batches;
- preserve object identity and event semantics at the JS boundary.

Do not attempt a broad generated-runtime rewrite.

## What not to do

- Do not confuse WebKit HTTP/disk cache with CPU L1/L2 locality.
- Do not place a large persistent WebKit cache on the 99%-full SD card.
- Do not add generic prefetch calls without PMU evidence.
- Do not rewrite the fbdev backend expecting major CPU-cache gains.
- Do not claim `-mcpu=cortex-a53` alone makes object-heavy JS cache-friendly.
- Do not replace PLAYABLE-V2 before identical-scene A/B validation.

## Decision

Proceed with **P0 instrumentation first**, then P1 and P2 as isolated experiments. P4 is justified only if PMU results show the WebProcess is materially cache-miss bound and the exact WPE build can be reproduced. PLAYABLE-V2 remains the rollback baseline.

## Execution results

### Implemented locally

- Added `scripts/device-benchmark.sh`, a bounded collector for PMU counters, `/proc` process statistics, cache topology, frequencies, thermal state, context switches, and CPU migrations. It falls back cleanly when `perf` is unavailable.
- Added real-process coverage in `tests/test-device-benchmark.sh`.
- Replaced the 1 ms evdev busy-poll loop with blocking `poll()` and a 100 ms shutdown bound.
- Added `evdev_wait.c/.h`, a pipe-backed behavioral test, a source integration contract, and strict host compilation checks.
- Added explicit build profiles through `scripts/build-flags.sh`:
  - `baseline`: `-O2`
  - `cortex-a53`: `-O2 -mcpu=cortex-a53 -mtune=cortex-a53`
  - `cortex-a53-o3`: `-O3 -mcpu=cortex-a53 -mtune=cortex-a53`
- The default build remains `baseline`; PLAYABLE-V2 behavior is not silently replaced.

### Native A/B build results

All three profiles built successfully as aarch64 artifacts in `wpebuild:cpp`.

| Profile | Launcher `.text` | Change from baseline | SHA-256 |
|---|---:|---:|---|
| baseline O2 + event-driven input | 537,549 B | baseline | `b3c6f12f2061fa0eed1e345ba0393c13616df6fe4c968ab1acf52bee6edcdbbb` |
| Cortex-A53 O2 + event-driven input | 542,941 B | +1.00% | `1155b9e197fcd95c2085687ee8265189db1fc5557ba4fcce52390068da1df5a3` |
| Cortex-A53 O3 + event-driven input | 729,341 B | +35.68% | `a7ad39996941e11d14248bf5786ec0432ce83461099f2a1c1b2015dc976a92b4` |

The O3 variant is rejected as the default candidate because its 35.68% code-size increase is contrary to the I-cache/locality objective. The A53/O2 variant remains the only tuned candidate for device A/B measurement.

Artifacts are preserved temporarily under `/tmp/moonrider-cache-ab-20260715/` in `baseline/`, `cortex-a53/`, and `cortex-a53-o3/`.

### Exact WPE source feasibility

The imported runtime was confirmed as Debian `wpewebkit 2.38.6-1`. Exact source artifacts were downloaded and checksum-verified against the Debian `.dsc` under the external backup directory:

- `wpewebkit_2.38.6.orig.tar.xz` — 30,521,576 bytes
- `wpewebkit_2.38.6.orig.tar.xz.asc`
- `wpewebkit_2.38.6-1.debian.tar.xz`
- `wpewebkit_2.38.6-1.dsc`

The source is about 311 MB extracted, but a WebKit build needs several GB of object storage. Available safe storage was only approximately 442 MB in tmpfs and 3.3 GB on the external backup volume. The root filesystem is deliberately excluded from large writes. A full build was therefore not started.

Debian's exact `debian/rules` also contains:

```text
-DWTF_CPU_ARM64_CORTEXA53=OFF
```

WebKit bug 197192 confirms that this option controls a JavaScriptCore workaround for Cortex-A53 erratum 835769; it is not a general cache optimization. It historically broke cross-builds and was intentionally disabled by Debian. Our GCC A53 native profile already enables compiler workarounds 835769 and 843419 for compiled C code, but that does not automatically retune JSC-generated machine code. Re-enabling the WebKit option without confirming the H700 core revision and running JSC tests would be unsafe.

### Current blockers

The handheld at the last-known address did not expose SSH. A full LAN port-22 scan found other machines but no RG40xx H SSH endpoint. Consequently these evidence-dependent operations remain pending:

- PLAYABLE-V2 PMU baseline;
- event-driven input smoke test on real evdev devices;
- baseline versus A53/O2 gameplay benchmark;
- CPU-affinity comparison;
- tuned deploy and rollback validation.

No experimental binary was deployed while the device was unreachable.
