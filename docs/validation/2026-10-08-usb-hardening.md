# USB capture hardening — 2026-10-08

Development branches only; no npm, desktop, or Android store release was published.
Target versions: library **1.0.18**, Sender **0.0.48**, Android **1.0.32**.

## Changes and regression checks

- Android presentation lead is capped at 16.7 ms for 30/60 FPS; the validated
  120 FPS budget remains unchanged. Seven Kotlin clock tests passed, including
  low-FPS cases that fail against the previous implementation.
- The old 19-second restart Surface delay coincided with an interstitial
  `AdActivity` taking the foreground. USB disconnect prompts now wait one second;
  display-size/configuration preparation or reconnection cancels pending work.
  An already displayed SDK ad still completes normally. Twenty JS regression
  tests cover cancellation, receiver transitions, and modal ownership.
- Native capture rejects legacy H.264 before encoder probing or display creation.
  Chromium's existing legacy path remains available; exact HEVC probes do not
  silently lower the selected resolution, FPS, or codec.
- Normal production builds exclude the four development capture routes and their
  chunks, benchmark IPC, and pattern IPC. User-facing stream/WebRTC troubleshooting
  stays available. Release commands rebuild production output first.
- Disconnect cleanup rechecks window/WebContents lifetime after awaiting the
  native helper. Both destroyed-window races failed before the fix and pass now.
  The final Sender regression run passed all 193 tests.
- npm packages exclude raw validation artifacts and diagnostic/reference Swift
  programs. Both architecture helpers remain included and signed. Package CI
  verifies clean installs and both exports on ARM and Intel runners; it has not
  been run remotely for these local changes.

## Physical evidence

Device: Samsung Tab S8+ SM-X806N, Android API 36, 120 Hz panel. Android
1.0.32/code 84 was signed with the existing local key and installed with
`adb install -r`; no uninstall or data wipe was performed.

| Path | Exact configuration | Observation |
| --- | --- | --- |
| Sender v0.0.47 source / new Android | Chromium, HEVC, 1920×1200, 60 FPS | 57.60 actual Surface presents/s over 20 s |
| New Sender production / new Android | Native, HEVC, 1920×1200, 30 FPS | 29.70 actual Surface presents/s over 20 s |
| Developer ID signed ARM Sender / new Android | Native, HEVC, 1920×1200, 60 FPS | 59.18 actual Surface presents/s over 20 s |

The old Sender is an exact v0.0.47 source rebuild with current local dependencies,
not the original published desktop binary. Surface measurements deduplicate the
middle `actualPresentTime` column of SurfaceFlinger latency history and divide new
presents by the host observation interval. They are not optical panel, distinct
image, or end-to-end latency measurements.

Three rapid restarts using old Sender source cancelled pending disconnect prompts
within 188–372 ms. Connected-to-first-Surface release took 85–105 ms; no ad took
the foreground during those restarts. A final intentional stop still displayed
the normal eligible ad after the delay. This confirms cancellation with an
eligible loaded ad, not merely a run where no ad was due.

A real cable detach destroyed the owned virtual display. Reattachment plus the
explicit Connect path recreated it and produced a frame; the user confirmed the
picture returned. Automatic connection was disabled in this isolated test
profile, so automatic reattachment was not claimed.

ARM and x64 packaged apps include library 1.0.18 and the correct unpacked helper.
Developer ID, hardened runtime, and deep/strict bundle verification passed.
The x64 helper launches under Rosetta but its hardware encoder probe reports
unsupported on this Apple M2; this is not Intel hardware validation.

Tablet display sleep removed the Surface while the USB session kept receiving.
After the user unlocked the tablet, a new Surface attached at 16:46:11.021 and
first-frame ACK arrived at 16:46:11.089; the user confirmed moving video returned.
The preceding time at the PIN screen is not a product recovery delay.

Real Mac lock at 16:47:27.050 stopped native capture; unlock at 16:47:32.147
restarted the helper on the same 2560×1600/120 Hz display, ready at 16:47:33.437.
Android frame counters resumed and the user confirmed the picture returned.

For the user's Apple-menu sleep/wake test, `powerd` recorded
`kIOMessageSystemWillSleep` / `Software Sleep` at 16:50:10.166. Native capture
stopped/recovered on the retained display; the user confirmed video returned.
The OS wake-end record is at 16:50:40.240. This is a short sleep/wake test, not a
long hibernation or USB power-cycle guarantee.

The first complex-content five-minute Surface sample measured 116.76 presents/s,
with a fresh endpoint and 108.66 ms maximum gap. This is an observed test result,
not the product's maximum: the external pattern generator sorted its accumulating
statistics every second on the display-link main thread and progressively slowed.
A separate quiet producer changes only the reporting timer to suppress that
observer overhead. Its fresh five-minute sample measured **116.72 presents/s**
(35,016 new timestamps / 300.013 s), valid overlapping coverage, no frozen
endpoint, p95 gap 8.359 ms, and maximum gap **217.32 ms**. The quiet producer
reported 119.92 submissions/s and no drawable, command, or deadline errors.
Removing observer overhead did not materially improve actual presents. Both
source tooling overhead and real queue backpressure exist; a locked 120 FPS or
an exact remaining bottleneck is not established. Further native default rollout
is gated on resolving/evaluating these occasional stalls.

The terminal AOA summary spans the whole 20-minute link, including screen lock,
sleep, and time at the tablet PIN screen. Its FPS/bitrate cannot describe the
five-minute moving-content interval. It records transfer/queue outliers, but
does not by itself establish which component initiated each stall.

## Release and compatibility gates

- Sender's permanent optional dependency and lock still resolve to registry
  1.0.17. Packaged execution was tested with the verified local 1.0.18 tarball;
  the temporary dependency replacement was restored afterwards. **Publish the
  verified 1.0.18 package, update dependency plus lock, and package again before
  releasing Sender.** Clean registry installation at the current lock cannot pass
  the new capture-helper packaging requirement.
- Developer ID signing passed; notarization and stapling were deliberately not
  requested for these local test artifacts. Actual Intel capture/USB execution
  remains unverified.
- Chromium remains the default. Native is explicit and requires HEVC capability,
  an exact successful configuration probe, and the packaged helper.
- Recent CAP1/probe-capable Android versions retain the USB wire format. New
  Android's `onTransmissionPreparing` is a local JS event, not a new wire frame.
  Old Android does not receive the new pacing/restart fixes. Native rejects apps
  lacking the required HEVC/probe capabilities; Chromium keeps the legacy path.

Detailed local evidence is under `/private/tmp/tabdisplay-hardening-20261008/`.
Local commits: library `0afa4a7`, Sender `21883ff`, Android `bc89bd4`.
The final signed copies additionally contain the shutdown guard from the final
Sender commit. Only the ASAR main entry and required integrity metadata were
updated before re-signing the app root; all other archived file contents and
unpacked helper bytes/signatures were compared against the first signed bundle.
The final ARM signed copy was actually run with both backends: Chromium HEVC
FHD60 continued presenting at 57.76/s in a ten-second smoke observation, and
native HEVC FHD60 reported ready plus first-frame ACK. Native-active quit no
longer logged the destroyed-window error. Cleanup left only main display ID 2,
no owned helper/pattern/app processes, and both app signatures still verified.
APK SHA-256: `fb8febfb8a643b39a21a029cb3941b298d9eed7eab804f8538f2969c5bb6ae9e`.
Library tarball SHA-256: `ea168db8b2cad00ccd5a7816ca9748223e1c0b5a05d1e685d0d836247fe43f7a`.
