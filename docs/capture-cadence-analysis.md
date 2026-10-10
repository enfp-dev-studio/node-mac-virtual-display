# Native 120 FPS diagnosis and fix

Two separate throttles explained the earlier result: the test renderer did not
present 120 distinct images, and an explicit ScreenCaptureKit `1/120` interval
reduced capture cadence even after the renderer was fixed. The production helper
now captures at native refresh when the selected FPS matches the actual display
mode. It retains the explicit interval when they differ.

The runtime has since moved to the private
[`node-mac-screen-capture` repository](https://github.com/enfp-dev-studio/node-mac-screen-capture).
Its helper is now `/Users/enfpdev/dev/node-mac-screen-capture/native/capture-helper.swift`
in the local checkout. The public virtual-display package ships no capture code.
Diagnostic producers and comparison drivers remain here and require an explicit
external capture-library path. Measurements and archived source hashes below
identify builds before this repository split; intermediate workspace-validation
snapshots remain historical evidence. Later application checks are recorded in
[the hardening report](validation/2026-10-08-usb-hardening.md).

## Controlled evidence, 2026-10-08

Apple M2, macOS 27.0.1 (26A434), owned 1280×720 @ 120 Hz displays. Hardware
measurements ran sequentially. A CAMetalDisplayLink producer rendered a changing
16-bit frame marker. Every encoded HEVC picture was decoded offline and matched
to its callback timeline; repeated marker IDs did not count as new frames.

| Same producer and display                                       | Distinct images/s |
| --------------------------------------------------------------- | ----------------: |
| Raw capture, fixed `1/120` interval, two runs                   |     108.5 / 103.3 |
| Raw capture, explicit zero interval, two runs                   |     118.1 / 118.5 |
| SideScreen original capture interval, 10 s ABBA controls        |     106.4 / 107.3 |
| Production native fix, intervening 10 s runs                    |     120.1 / 120.0 |
| SideScreen encoder with explicit native-interval override, 30 s |            119.73 |
| Native fix with the same capture configuration, 30 s            |            119.27 |

The ABBA order was reference → native → native → reference on one continuously
running producer. The 30-second comparison also used one continuous producer.
Both paths encoded HEVC Main, 60 Mbps / ultralow. Reference means the unmodified
SideScreen VideoEncoder compiled with our capture driver, not the entire app.
The native-interval override is explicitly labeled; it is not SideScreen's
original capture setting. One-frame measurement boundaries can yield 120.1
in a ten-second window. Nominal 120 FPS does not mean every one-second window
contains exactly 120 new images: the native 30-second run ranged from 117 to 121.
All decoded markers were valid. Native passed a 95% distinct-FPS threshold.

With the final event-loop fix, 2560×1600 @ 120 Hz also passed 30-second checks:
118.70 distinct FPS through native capture, 118.57 through the SideScreen encoder
with the same explicit native interval, and 118.17 through the real sender adapter.
The sender's USB sink was simulated. All markers were valid; this establishes
nominal 120-FPS capacity at the tested size, not perfectly uniform 120-FPS pacing.

Apple's local SCStream header explicitly permits a zero minimum interval to
capture at native display refresh. The measured native period was 8.333375 ms,
slightly _longer_ than 1/120 second. The A/B evidence establishes the interval
setting as the remaining bottleneck; it does not establish Apple's internal
scheduling/phase mechanism or a simple floating-point precision explanation.

## Why the first fixture reported about 60

The buffered AppKit fixture's timer ran 120 times per second, but raw capture
contained approximately 56–60 different images/s. In its first 128 observed IDs,
125 of 127 transitions advanced by two. WindowServer display-time intervals were
mostly 16.67 ms despite the CG mode and CVDisplayLink reporting 120 Hz.
Layer backing plus an explicit transaction flush raised distinct raw capture to
approximately 97–108 FPS. Neither change alone produced that improvement.
Changing pixel format, capture API or disabling all pixel reads left the original
fixture near 60. The final producer uses CAMetalDisplayLink-supplied drawables
and GPU rendering, rather than a free-running AppKit timer.

Metal drawable `presentedTime` was zero on these virtual displays despite valid
changing captured images. It is not used as evidence of presentation or drops.
An exploratory renderer that stopped producing heartbeats is excluded.

## Encoder and queue controls

The unchanged SideScreen encoder independently sustained 119.7–120.0 callbacks/s
with bounded synthetic NV12 input and no unfinished submissions. Its 64 source
states repeat, so that test establishes encoder capacity, not 120 distinct images.
Production profiling found no dominant Node pipe/Annex-B queue bottleneck.
Complete input, cached replay, actual pending-frame replacement, VideoToolbox
reported drops and output queue delay are recorded separately. Signed capture
PTS/host-clock offsets include future presentation timestamps; their positive
subset must not be presented as overall capture latency.

An additional runtime mode-change regression exposed a separate notification
problem: `dispatchMain()` did not deliver CG mode changes in the helper. Registering
the observer on the main thread and running the AppKit event loop fixed it.
Four real 60↔120 Hz changes now reconfigure correctly without spending the
failure retry budget, while selected 60 FPS remains enforced. Removed display
IDs can return `-1` from CG online/active queries on this OS; independent cleanup
checks use online/active display-list membership and the absence of a current mode.

## Physical Android boundary

Real USB and the full Electron Sender were subsequently tested on Samsung
SM_X806N / Android API 36 at 2560×1600 @ 120, HEVC, 60 Mbps / ultralow.
The unchanged receiver completed USB delivery near 119 FPS and passed product
start/stop/same-cable restart, while deduplicated SurfaceFlinger layer-present
cadence remained about 107 FPS. This identified a separate receiver-side boundary
after the host capture/encoder bottlenecks above had been resolved.

A control receiver APK measured 108.82 FPS with legacy timing and 106.52 FPS
with input-anchored two-frame lead. A later diagnostic APK produced a stronger
same-installed-binary output → input → output comparison without reinstalling:
117.52 → 108.43 → 116.81 FPS. These roughly 32-second compositor histories include the first snapshot's
pre-sampling history. They are separate from USB's 45-second actual-window
measurement and the newer sampler's observation-window FPS. The output anchor
maps media PTS into Android time after decoding, with a bounded presentation lead.
The final default receiver, with diagnostic intent modes removed, measured
117.79 layer presentations/s in the new 32.04-second observation-window sampler
and 118.93 completed USB frames/s over 45.00 seconds. Full Electron Sender then
measured 117.11 layer presentations/s over 32.00 seconds, passed start/stop and
same-cable restart, and removed its owned displays. Both final paths passed the
95% mean threshold for selected 120 FPS. Product's moving-window wire rate was
not separately measured; its later static restart transport summary is excluded.

The median layer-present interval was about 8.358 ms (cadence near 119.64 Hz);
the device reports 120 Hz. This is not an optical panel refresh measurement,
a count of distinct decoded images, or end-to-end latency. Simple-pattern wire
traffic near 1.51 Mbps does not establish full 60 Mbps USB capacity. Sender's
`docs/native-usb-capture-spike.md` keeps this experiment separate from
`docs/validation/2026-10-08-native-usb-physical-baseline.json`, and saves the final
source hashes/APK identity and observations in
`docs/validation/2026-10-08-native-usb-physical-fixed.json`. Receiver changes are
local commit `fdc606c`; this coexisting debug-signed release APK is not a distribution validation.

## Reproduce

Build and validate capture independently in its own checkout. Raw JSON and
research diagnostic sources remain in this virtual-display repository and are
excluded from runtime tarballs.

Requires a logged-in GUI session, Screen Recording permission and macOS 14+ for
the display-clock test producer. Capture itself supports macOS 13+.

```sh
cd /Users/enfpdev/dev/node-mac-screen-capture
npm ci
npm run build:ts
npm run build:prebuilds
npm test
task_archive="$(npm pack --ignore-scripts --pack-destination /private/tmp --silent)"
npm run test:package -- "/private/tmp/$task_archive"

cd /Users/enfpdev/dev/node-mac-virtual-display
npm ci --ignore-scripts
npm run build
xcrun swiftc -O native/capture-cadence-metal.swift -o /private/tmp/node-vdisplay-cadence-metal
node scripts/compare-capture-throughput.cjs --capture-library=/Users/enfpdev/dev/node-mac-screen-capture --reference=/path/to/SideScreen --seconds=10 --order=reference,native,native,reference
node scripts/compare-capture-throughput.cjs --capture-library=/Users/enfpdev/dev/node-mac-screen-capture --reference=/path/to/SideScreen --seconds=30 --reference-interval=native
xcrun clang++ -fobjc-arc -std=c++17 -framework Cocoa -framework CoreGraphics native/diagnostic-display-modes.mm -o /private/tmp/node-vdisplay-mode-fixture
node scripts/validate-capture-display-modes.cjs --capture-library=/Users/enfpdev/dev/node-mac-screen-capture
```

The repository's `docs/validation/2026-10-08-native-capture-fixed.json` records
source hashes, decoded counts and the independent geometry/quality checks.
`docs/validation/2026-10-08-capture-cadence.json` is retained there as historical
diagnosis, including failures before the fix. Intel execution,
real cable unplug/replug, screen lock, sleep/wake and long-duration stability
remain unverified. Physical reception and receiver layer presentation have the
separate measured scope above. These local tests establish nominal 720p120 and 2560×1600@120 capacity,
not the maximum resolution/FPS of every host or receiver.
