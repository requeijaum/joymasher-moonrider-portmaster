# WPE WebKit 2.42.5 ARM64 Pilot — 2026-07-15

## Status

A deployable, non-destructive WPE WebKit 2.42.5-1 ARM64 engine overlay was assembled and verified locally. It has **not** been deployed because the RG40xx H was offline during this work.

The PLAYABLE-V2 runtime and game assets were not modified.

## Candidate rationale

WPE WebKit 2.42.5-1 is the lowest-risk upgrade step from 2.38.6 because it:

- keeps the `libWPEWebKit-1.1.so.0` SONAME;
- keeps API version 1.1 and libsoup 3;
- predates Debian's `t64` package transition;
- was built against glibc 2.37-era Debian unstable;
- can be tested without first porting the launcher to WPE API 2.0.

This pilot does not claim to enable CPU cache or specifically mitigate Cortex-A53 erratum 835769.

## Provenance

Engine package:

- package: `libwpewebkit-1.1-0_2.42.5-1_arm64.deb`;
- Debian Snapshot first-seen timestamp: `2024-02-06T16:33:51Z`;
- Snapshot object: `e9c89fd6265de7e5e1889e6f4d0ca825beadcbd6`;
- SHA-256: `e672c300944a9f69e21153f84e0108486bdd88eaad8b6ada89ce5876ab85d2fc`.

All imported packages and hashes are recorded in `manifests/WPE-2.42.5-PILOT.sha256`.

Local preserved workspace:

```text
/media/rafaelfrequiao/Livinha/Portsmaster/wpewebkit-pilot-2.42.5-1
```

## ABI audit

Compared with WPE WebKit 2.38.6:

- SONAME remains `libWPEWebKit-1.1.so.0`;
- old/new exported symbols: 943/995;
- common exports: 941;
- two removed symbols are private `WebKitExtensionManager` C++ symbols;
- the matching 2.42 injected bundle is included, so it does not depend on the old private pair;
- all 17 WPE/WebKit/JSC symbols used by `moonrider-launch` resolve in the pilot runtime.

The launcher therefore does not require an API port for this candidate.

## Runtime version requirements

Observed maximum requirements among the newly imported files:

```text
GLIBC_2.36
GLIBCXX_3.4.32
CXXABI_1.3.15
```

The WPE engine itself requires at most `GLIBC_2.35`; `GLIBC_2.36` comes from the bundled GCC 14 `libstdc++.so.6.0.33`.

The target muOS runtime has glibc 2.38, so the GLIBC floor is compatible. A matching `libstdc++` is carried in the overlay rather than assumed from the device.

## Minimal dependency closure

The 2.42 engine adds these direct runtime dependencies relative to 2.38:

- `libgsttranscoder-1.0.so.0`;
- `libjxl.so.0.7`;
- `libavif.so.16`;
- `libdrm.so.2`;
- a `libstdc++.so.6` exporting `GLIBCXX_3.4.32`.

AVIF/JXL then require their codec libraries. The closure was built from actual ELF `DT_NEEDED` edges rather than installing Debian's complete dependency set. This avoided pulling systemd, Mesa, X11 servers and 216 unrelated packages.

Final closure comparison:

```text
PLAYABLE-V2 closure files: 50
WPE 2.42 pilot closure files: 82
new external SONAME requirements: 0
result: CLOSED_OVER_DEVICE_BASELINE
```

The overlay supplies 32 additional closure members. No new library is expected from the device beyond the external SONAME set already used by PLAYABLE-V2.

## Artifacts

Full diagnostic staging:

```text
/media/rafaelfrequiao/Livinha/Portsmaster/wpewebkit-pilot-2.42.5-1/pilot-runtime
```

Size: 314 MB.

Deployable engine overlay:

```text
/media/rafaelfrequiao/Livinha/Portsmaster/wpewebkit-pilot-2.42.5-1/device-overlay
```

Properties:

- size: 121 MB;
- regular files: 108;
- proprietary game assets: none;
- complete per-file hash manifest: `device-overlay.sha256` in the preserved workspace.

Core hashes:

```text
a8518d787f10867ede8196088773bd60ea688aff63ac1b05223cbee6e6838e45  libWPEWebKit-1.1.so.0.6.5
559a5a09825602313657d7e6cca59865b69cb8e4a93338573ee76b81addf4ab6  WPEWebProcess
8c6bc3d48e369fd6065c1c57c96d6f24b4018894ad357941b2605ec4c25ae6e6  WPENetworkProcess
```

## Runtime selection hook

`runtime-config/run-moonrider.sh` now accepts:

```text
MOONRIDER_WPE_ENGINE_DIR=/path/to/runtime-wpe-2.42
```

When unset, `ENGINE` defaults to `HERE`, preserving PLAYABLE-V2 behavior exactly. When set, only these paths are redirected:

- first `LD_LIBRARY_PATH` entry;
- `WEBKIT_EXEC_PATH`;
- `WEBKIT_INJECTED_BUNDLE_PATH`.

The backend, launcher, GStreamer plugin path, glX stub, mixer and game assets remain from PLAYABLE-V2.

The hook was added with a RED/GREEN contract test: `tests/test-wpe-engine-overlay.sh`.

## Verification completed

- package SHA-1 matched the Debian Snapshot object;
- package and dependency SHA-256 hashes recorded;
- ARM64 architecture confirmed;
- ELF `DT_NEEDED` closure completed;
- no new unresolved SONAME relative to PLAYABLE-V2;
- launcher API symbols resolved 17/17;
- maximum GLIBC/GLIBCXX/CXXABI requirements audited;
- engine/process checksums verified after assembly;
- shell syntax passed;
- all repository shell tests passed;
- `git diff --check` passed.

## Device deployment and smoke result

The device became reachable at `192.168.1.115` on 2026-07-15.

Pre-deployment state:

- `/mnt/mmc`: 19 GB free;
- `/mnt/sdcard`: 570 MB free;
- PLAYABLE-V2 runtime remained at `/mnt/union/ports/moonrider/runtime`;
- no Moonrider or WPE processes were running.

The pilot was deployed separately to:

```text
/mnt/mmc/moonrider-wpe-2.42
```

The target filesystem does not implement symbolic links. The first normal `rsync` therefore stopped with `Function not implemented`. A FAT-compatible closure was then assembled with every required SONAME stored as a regular file:

- recursive closure: 77 libraries;
- engine libraries copied: 33;
- files in the FAT overlay: 38;
- symlinks: zero;
- compact FAT overlay size: 113 MB;
- remote hashes: passed.

The interrupted first transfer left harmless versioned target files beside the FAT-compatible closure, so the current remote directory occupies 235.5 MB. They were not removed because cleanup is unnecessary for function and would be destructive.

### Injected bundle correction

WPE 2.42 contains the compiled directory:

```text
/usr/lib/aarch64-linux-gnu/wpe-webkit-1.1/injected-bundle/
```

`WEBKIT_INJECTED_BUNDLE_PATH` does not override this path in the tested binary. The initial smoke therefore tried the PLAYABLE-V2 injected bundle and reported the private-symbol mismatch:

```text
WebKitExtensionManager::singleton()
```

The game still loaded, but the mismatch was corrected. `scripts/patch-wpe-injected-bundle-path.py` performs an atomic, fixed-size, single-occurrence patch to:

```text
/mnt/mmc/w42/injected-bundle/
```

The replacement is shorter and NUL-padded, so no ELF offsets or file size change. A synthetic RED/GREEN test covers successful replacement, unchanged size and rejection of ambiguous duplicate occurrences.

Patched device hashes are recorded in `manifests/WPE-2.42.5-DEVICE-PILOT.sha256`.

### Controller and lifecycle

`mr-ctl.sh` now provides:

```text
run [SECONDS]       # PLAYABLE-V2 / WPE 2.38
run42 [SECONDS]     # isolated WPE 2.42 pilot
log / rawlog        # baseline logs
log42 / rawlog42    # pilot logs
```

Frontend teardown no longer invokes muOS `FRONTEND stop`, whose implementation contains a `KILL` fallback. The controller uses exact frontend PIDs and this sequence:

```text
USR1 -> timed wait -> TERM -> timed wait -> STOP only if still alive
```

Restoration removes `/tmp/safe_quit`, restores the native frontend environment, resumes any frozen exact PIDs, waits for their exit, and starts `FRONTEND start launcher` when required. No `kill -KILL` or broad `pkill` is used.

### Executed smoke test

The final hardware smoke used `mr-ctl.sh run42 8`. Observed results:

- WPE 2.42 library selected from `/mnt/mmc/moonrider-wpe-2.42`;
- loader trace had no `not found` dependency;
- Mali/fbdev backend created at 640x480;
- `WebKitWebView` created;
- native mixer initialized;
- gamepad shim V3 installed;
- audio ghost V12 IPC installed;
- page reached `LOAD_FINISHED`;
- patched injected bundle produced no undefined-symbol warning;
- no segfault, abort, assertion, fatal error or traceback;
- launcher main loop ended cleanly;
- controller recorded `exit=0`;
- `frontend.sh` and `muxfrontend` were both alive after restoration and remained alive after an additional eight-second stability check.

This proves boot, loader closure, EGL/fbdev initialization, JavaScript startup and lifecycle on hardware. It does not yet prove subjective audio correctness, PLAYPAIR handoff, every SFX, physical controls during gameplay, frame pacing or long-play stability.

## Rollback

The PLAYABLE-V2 engine was not overwritten. Immediate rollback is:

```text
/mnt/mmc/mr-ctl.sh run
```

The standard PortMaster launcher also remains on the PLAYABLE-V2 path. The WPE 2.42 pilot is selected only by `mr-ctl.sh run42`.
