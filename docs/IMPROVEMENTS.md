# Stability & Correctness Improvements

This document captures the display-management improvements adopted in this
library. Most of the patterns were derived from a review of
[SideScreen](https://github.com/tranvuongquocdat/SideScreen)'s
`VirtualDisplayManager` (notably its fix for issue #39: a virtual display
re-adopted as the main display by WindowServer, leaving the menu bar, dock, and
keyboard focus on an invisible screen). SideScreen is MIT-licensed; see
[Acknowledgements](#acknowledgements) below.

## 1. HiDPI physical / logical resolution handling

### Before
The descriptor's `maxPixels*` were set to the **logical** resolution, and HiDPI
was modelled as an extra `width/2` "half-res" mode. This is the reverse of how
macOS expects HiDPI to be described, so macOS did not reliably recognise the
display as Retina.

### After
The descriptor now describes **physical (backing) pixels**, which are `2x`
logical when HiDPI and `1x` otherwise:

- `descriptor.maxPixelsWide/High` = `physW × physH` (`width*2`, `height*2` when HiDPI).
- `descriptor.sizeInMillimeters` is computed from the **physical** size.
- The effective PPI is forced to **220** when HiDPI (≥200 is the threshold at
  which macOS treats a display as Retina), so the display is recognised as
  high-density.

The settings expose a pair of modes for HiDPI:

1. **Anchor mode** at the physical resolution — tells macOS the display is
   high-density and unlocks HiDPI.
2. **Logical mode** at the requested resolution — the resolution the user sees.

Non-HiDPI uses a single mode at the requested resolution.

### Verification
Creating `1920x1080 @ 60Hz` with `hiDPI: true` reports
`actualWidth/actualHeight = 3840x2160` (2x). The same resolution with
`hiDPI: false` reports `1920x1080` (1x). See the integration test
`creates a HiDPI display with physical = 2x logical resolution`.

## 2. Persistent main-display guard

### Before
The physical-main invariant (a physical display must own the main slot whenever
one is online) was only enforced **once, at creation time**, in
`PostProcessDisplay`. If WindowServer later re-adopted the virtual display as
main — e.g. when a physical display was hot-plugged — nothing corrected it.

### After
After creation, `RegisterScreenParamsObserver` subscribes to
`NSApplicationDidChangeScreenParametersNotification`. On **every**
display-topology change, `EnsurePhysicalDisplayStaysMain` runs the safety net:

- If the virtual display is currently the main display **and** at least one
  physical display is online, the first physical display is moved to the main
  slot `(0,0)` and the virtual display is parked to its right.
- This is a no-op in true headless operation (no physical display online).
- The observer is removed in `RemoveScreenParamsObserver` (called from
  `ReleaseDisplayObjects`), so cleanup is idempotent and the display is not
  re-guarded after destruction.

### Verification
Behaviour is exercised by the integration suite; each test tears down its
display in `afterEach` so failures never leak an orphaned display.

## 3. Online physical-display filtering

`OnlinePhysicalDisplays` enumerates online displays and filters out:

- the library's **own** virtual display, and
- any **stale virtual display** registered with vendor ID `0xEEEE` (the vendor
  the descriptor uses), so a leftover display from a previous run is never
  mistaken for a physical screen.

This mirrors SideScreen's `onlinePhysicalDisplays()` helper.

## 4. Configuration scope persists beyond the app

### Before
Display configuration was completed with `kCGConfigureForAppOnly`, so layout
changes were discarded when the app exited.

### After
`PostProcessDisplay` and `EnsurePhysicalDisplayStaysMain` complete the
configuration with `kCGConfigureForSession`, so the arrangement persists for
the rest of the login session. (SideScreen uses `.permanently`/`.forSession`
for mirror/position changes; session scope is the right default for a library,
avoiding writes to WindowServer's permanent preferences that can make it
re-adopt a virtual display as main on later startups.)

## 5. Frame-rate contract

- **`createVirtualDisplay`** accepts a **positive integer** `frameRate`
  (validated with `Number.isInteger` in the JS wrapper) and clamps it to
  30–120 Hz in the native layer.
- Returned rates are reported **as-is**:
  - for `create`, the integer the user supplied;
  - for `clone`, the actual mode rate reported by macOS (which can be a
    fractional value such as `59.94 = 60000/1001`). These are **not rounded**,
    matching how Windows and the display stack label fractional rates.

The exact fractional value is always used internally to build the
`CGVirtualDisplayMode`, so a cloned 59.94 mode is created as 59.94.

## 6. Fresh-display mode fallback

A newly created virtual display may not have a settled `CGDisplayMode` yet, so
`CGDisplayCopyDisplayMode` can report `0x0`. `getDisplayInfo` therefore falls
back to the descriptor's physical pixels (for HiDPI these are exactly `2x`) and
to the requested refresh rate when the live mode is not yet available. This
makes `actualWidth`/`actualHeight` reliable immediately after creation.

## 7. Test coverage

The test suite was expanded from a single smoke test to **12 tests** split into
two layers:

1. **JS-layer validation** (safe on any platform, no display created) — asserts
   bad inputs throw: non-integer/zero width and height, non-positive/fractional
   `frameRate`, non-positive PPI, non-numeric width.
2. **Integration** (macOS only) — creates real virtual displays and verifies
   `createVirtualDisplay`/`getDisplayInfo` output, the HiDPI 2x contract, that
   `getDisplayInfo` returns `null` after destroy, and that destroying a
   non-existent display returns `false`. Each test tears its display down in
   `afterEach`.

## Acknowledgements

Several of the display-management patterns above — the persistent main-display
guard (§2), the online-display filtering by vendor ID (§3), and the
session-scoped configuration scope (§4) — were derived from a review of
[SideScreen](https://github.com/tranvuongquocdat/SideScreen)
(`MacHost/Sources/VirtualDisplayManager.swift`), released by
[Tran Vuong Quoc Dat](https://github.com/tranvuongquocdat) under the
[MIT License](https://github.com/tranvuongquocdat/SideScreen/blob/main/LICENSE).

The techniques were adopted conceptually rather than by copying code, but the
attribution is kept here to acknowledge the source and to satisfy the MIT
license's request to include the original copyright notice where substantial
portions are reused. No code from SideScreen is vendored in this repository.
