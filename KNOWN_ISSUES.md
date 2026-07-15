# Known issues

This is a development preview tested only on an Anbernic RG40xx H running muOS 2508.4 LOOSE GOOSE. Do not present it as a stable or broadly compatible PortMaster release.

## Performance

Observed gameplay is approximately **23 fps**, with visible slowdowns to **7 and 13 fps** in the tested WPE WebKit 2.38 baseline. These numbers were read on-device by the operator, not produced by an automated benchmark.

The underlying performance bottleneck has not been isolated. Candidate areas include Construct 2 JavaScript execution, WebKit scheduling, EGL/GLES rendering and frame pacing.

## Input backlog during slowdown

Diagnostic instrumentation measured JavaScript acknowledgements as high as **1.79 s**, while evdev and the launcher's GLib main loop continued to run.

When the WebProcess catches up, historical gamepad snapshots can execute in a burst. The current read-count latch may then expose phantom simultaneous button combinations to Construct 2. This can make controls appear stuck or incorrect after a slowdown or black frame.

The evidence and exact event sequences are preserved on the public branch `diagnostics/input-stall-20260715`. No corrective input policy has been merged into `main`.

## Exit and teardown

The L2 + R1 double-press exit path can become unavailable during a severe stall. A prior stalled run also left the launcher wrapper alive after `TERM`; no forced kill was used. Reboot may be required during development testing.

## Compatibility

Only RG40xx H / H700 / Mali-G31 with muOS 2508.4 has been tested. ArkOS, AmberELEC, Knulli, ROCKNIX, other Anbernic models and other SoCs remain unverified.

## Distribution

Commercial game assets are never included. A legitimate desktop/Electron copy is required. The source repository also does not currently ship the large WPE runtime; see the release notes for the exact artifact status.
