# Native capture reference comparison

The native feature follows SideScreen revision
`9b0ac6d671b67e6d36ccde48d41c84cf636b616d`, using its production
`ScreenCapture.swift`, `VideoEncoder.swift`, and actual settings defaults.
The [MIT notice](../THIRD_PARTY_NOTICES.md) is retained here for provenance;
a copy ships with the separate capture library.

## Repository boundary after the split

The runtime now lives in the private
[`node-mac-screen-capture` repository](https://github.com/enfp-dev-studio/node-mac-screen-capture),
locally checked out at `/Users/enfpdev/dev/node-mac-screen-capture`. Its runtime
source is `src/index.ts` and `native/capture-helper.swift` in that checkout.
Applications import `@enfp-dev-studio/node-mac-screen-capture`, replacing the
former unpublished `node-mac-virtual-display/capture` entry. The public npm
package manages virtual displays only; USB transport and receiver compatibility
stay in Sender.

Capture is unpublished and its package is `private: true`. Sender can vendor its
packed tarball and ship signed helpers with the required MIT notices without
npm publication. Private repository access protects the new source checkout;
previously committed public source remains in Git history. Reference producers
and experiment drivers remain under this repository's `native/` and `scripts/`
and require an explicitly selected external capture library.

Measurements below describe recorded experiments before the standalone
repository split. Their paths, hashes and test counts identify those builds;
moving code does not revalidate the new library. Archived intermediate
workspace-validation snapshots are retained as historical evidence. Later
application hardening has separate evidence in
[the hardening report](validation/2026-10-08-usb-hardening.md).

## Recorded implementation before policy simplification

The retry budget and wake restart described below belong to the recorded
experiment. They were removed from the current standalone SDK. Its current
contract is documented in that repository's README; these measurements do not
validate the simplified implementation.

- ScreenCaptureKit uses video-range NV12, queue depth 4, `scalesToFit=false`,
  a clear background and cursor inclusion.
- When the fresh CG display refresh matches the selected FPS within 0.001 Hz,
  an explicit zero minimum interval uses native refresh. Otherwise `1/FPS`
  remains enforced. `ready.captureTuning` and recovery events expose this choice.
- VideoToolbox requires hardware encoding, 8-bit Main profile, no B frames,
  BT.709, a one-second GOP and the exact selected size, FPS and bitrate.
- Quality presets match the reference: 0.5, 0.65, 0.8, 0.9 and 0.3.
  Applied/unsupported optional properties report their OSStatus.
- Idle callbacks replay the last native buffer. Complete captures and cached
  replay counters are separate; neither callback count alone proves new images.
- Stream/encoder errors and wake events trigger bounded same-config recovery.
  Two consecutive failure restarts are allowed, reset after 30 healthy seconds.
  Normal display-mode changes reconfigure without spending this failure budget.
  Generations reject stale callbacks; output resumes with a keyframe and
  strictly increasing timestamps.
- A display-idle sleep assertion is held while streaming. Frame ownership and
  the Node helper pipe are bounded. USB AOA and decoder checks stay in sender.

SideScreen's regular encoder enforces a 60 Mbps floor; its application defaults
to 1000 Mbps. Sender's opt-in native path selects 60 Mbps / ultralow with explicit
bitrate/quality overrides. Chromium remains at 20 Mbps. The reference's automatic
resolution scaling and CGDisplayStream fallback are not enabled.

## Observed on 2026-10-08

Apple M2, macOS 27.0.1. Owned displays only; HEVC Main, 60 Mbps / ultralow.

| Display                        | Complete capture samples/s | Delivered encoded samples/s |
| ------------------------------ | -------------------------: | --------------------------: |
| 1920×1080 @ 60                 |                      59.11 |                       59.86 |
| 1280×720 @ 120                 |                     117.67 |                      118.86 |
| HiDPI 960×540 → 1920×1080 @ 60 |                      58.11 |                       59.11 |

These eight-second quality/recovery measurements passed the 95% FPS threshold.
Complete-input statistics and delivered output use separate timing windows.
Independent decoding verified exact physical size, Main profile/Main tier,
borders, checker detail, text and color-bar luma on the first decoded frame.
Those static-region checks do not establish sustained motion fidelity.
Quality 0.5 was accepted; zero-frame-delay was unsupported (`-12900`) and is
reported explicitly. Configured bitrate is a target, not measured USB traffic.

A separate continuously changing marker test verified decoded _distinct_ images:
120.1 and 120.0 FPS in ten-second runs, and 119.27 FPS over 30 seconds. The original
SideScreen capture interval delivered 106.4–107.3 distinct FPS on the same source;
its unmodified encoder with an explicit native-interval override delivered
119.73 FPS over 30 seconds. This is a component comparison, not a full SideScreen
application benchmark. See the [diagnosis and controls](capture-cadence-analysis.md).

The final build also passed 30 seconds at **2560×1600 @ 120**: native capture
118.70 distinct FPS, the SideScreen encoder with the same native interval 118.57,
and the actual sender adapter 118.17. Every measured marker was valid. The sender
sink simulates USB; no physical receiver was attached. The 95% threshold applies
to mean distinct throughput, not a guarantee of 120 different images every second.

Explicit restart recovered in 407–420 ms and began with an IDR. Requested
keyframes arrived in 4.5–8.1 ms. There were no frames after stop or stop during
restart. These are local fixture timings, not USB or receiver display latency.

The helper processes display notifications on an AppKit event loop. A real
60→120→60→120→60 Hz test retained selected 60 FPS (57.96–60.01 measured after
settling), reconfigured four times without exhausting the failure budget, and
resumed each time with an advancing keyframe. A separate process verified the
owned display was removed after the fixture exited; the main display stayed unchanged.

Physical Android USB was subsequently tested on SM_X806N / Android API 36 at
the same 2560×1600 @ 120, HEVC, 60 Mbps / ultralow target. The original receiver
passed real USB delivery and full Electron Sender start/stop/same-cable restart,
but SurfaceFlinger layer presentation remained about 107 FPS. A coexisting
diagnostic receiver with output-anchored Android presentation timing measured
116.81–117.52 FPS in repeated roughly 32-second compositor histories. The final
default receiver then measured 117.79 FPS over a 32.04-second observation window,
with real USB at 118.93 FPS. Full Electron Sender measured 117.11 layer
presentations/s over 32.00 seconds and passed start/stop/same-cable restart;
independent CG checks confirmed owned displays were removed. Both final paths
passed a 95% mean threshold for selected 120 FPS. These are layer-present
timestamps, not optical panel or distinct-image measurements. Simple-pattern
traffic was about 1.51 Mbps, so full 60 Mbps USB bandwidth remains unverified.
The separate baseline and later experiment are recorded in Sender's
`docs/native-usb-capture-spike.md` and
`docs/validation/2026-10-08-native-usb-physical-baseline.json`, with the final
default receiver and product results in
`docs/validation/2026-10-08-native-usb-physical-fixed.json`. The receiver fix is
local commit `fdc606c` on `codex/native-usb-render-pacing`; the local coexisting
debug-signed release APK preserves the original receiver installation and is not a release.

At this recorded checkpoint, the library's 33 protocol/input tests, TypeScript
and lint passed. Both helper architectures compiled and verified ad-hoc signatures.
Real cable unplug/replug,
screen lock, real sleep/wake, Intel hardware encoding, signed/notarized distribution and
long-duration stability remain unverified. The feature remains experimental on
`codex/native-screen-capture`; no capture release has been published.

## Reproduce

Build, test and pack capture in its own repository:

```sh
cd /Users/enfpdev/dev/node-mac-screen-capture
npm ci
npm run build:ts
npm run build:prebuilds
npm test
task_archive="$(npm pack --ignore-scripts --pack-destination /private/tmp --silent)"
npm run test:package -- "/private/tmp/$task_archive"
```

Build the virtual-display addon and run the retained experiment from this
repository, explicitly selecting the external capture library. Raw validation
JSON and reference-only diagnostic sources stay here and are excluded from
runtime tarballs.

```sh
cd /Users/enfpdev/dev/node-mac-virtual-display
npm ci --ignore-scripts
npm run build
node scripts/smoke-native-capture.cjs --capture-library=/Users/enfpdev/dev/node-mac-screen-capture
```

`validate-reference-capture.cjs` is an archived restart-policy experiment. It
requires an older SDK exposing `requestRestart()` and rejects the current SDK
before creating any display. It is not a current validation command; retain it
only to reproduce the corresponding historical source and evidence.

The independent display-clock producer requires macOS 14+. All displays/windows
are owned and removed by the test. The original buffered AppKit fixture remains
available with `--pattern-mode=appkit-buffered` for reproducing the historical
fixture bottleneck. The reference driver compiles the original VideoEncoder
without modifying the reference checkout.

Current evidence (`docs/validation/2026-10-08-native-capture-fixed.json`) and
historical pre-fix evidence (`docs/validation/2026-10-08-native-capture.json`) in
the Git repository are labeled separately. Cached replays cannot satisfy the
distinct-image throughput check.
