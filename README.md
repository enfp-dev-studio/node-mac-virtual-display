# node-mac-virtual-display: Native Library for Virtual Display on macOS

A native library for macOS to create virtual displays for your applications using Node.js. This library uses CoreGraphics and CoreDisplay APIs to provide an interface for creating and managing virtual displays on macOS. This library is used in [Tab Display](https://tab-display.enfpdev.com), a service that allows iPads and Android tablets to be used as portable monitors.

## Features

- [x] Create and Destroy single virtual displays on macOS.
- [x] Configurable display resolution and refresh rate.
- [x] Create a virtual display by cloning the main display.
- [x] Added option to select between Mirror and Extend display modes.
- [x] Reports requested and currently active display mode information.
- [x] Query live display state via `getDisplayInfo()`.
- [x] HiDPI support: physical (backing) resolution = 2x logical, with an anchor
      + logical mode pair so macOS recognises the display as Retina.
- [x] Persistent main-display guard: keeps the menu bar, dock, and keyboard
      focus on a physical display whenever one is online (never on an invisible
      virtual screen), even after display topology changes such as hot-plugs.
- [ ] Support for multiple virtual displays.

> See [docs/IMPROVEMENTS.md](docs/IMPROVEMENTS.md) for the HiDPI, main-display
> guard, and refresh-rate design notes and how they were verified.

## Requirements

- macOS 10.14 or later
- Node.js 22 or later

## Installation

Use npm to install the library:

```shell
yarn add node-mac-virtual-display
```

### Cross-platform projects

This package declares `"os": ["darwin"]`, so package managers know it only
applies to macOS. If your project also builds on Windows or Linux, declare it
as an **optional** dependency:

```json
{
  "optionalDependencies": {
    "node-mac-virtual-display": "^1.0.15"
  }
}
```

Both parts are needed. With `optionalDependencies`, the `os` field makes
package managers skip the download and the `node-gyp` build entirely on
non-macOS platforms. Listed under regular `dependencies`, the `os` field alone
does not prevent installation — the package is still fetched and the native
build still runs, and fails.

Guard the require at runtime too, since the module will be absent on other
platforms:

```js
let VirtualDisplay = null
if (process.platform === 'darwin') {
  VirtualDisplay = require('node-mac-virtual-display')
}
```

Importing the types has the same constraint: `import type` still makes
TypeScript resolve the `.d.ts`, which fails on platforms where the package was
skipped. Declare the shape you need locally instead.

## Usage

To create/destroy a virtual display:

```javascript
const VirtualDisplay = require('node-mac-virtual-display')
const vdisplay = new VirtualDisplay()
// Clone primary display
vdisplay.cloneVirtualDisplay({
  displayName: "Clone Display",
  mirror: true
})
// OR
// To create a virtual display:
vdisplay.createVirtualDisplay({
  width: 1920,
  height: 1080,
  frameRate: 60,
  hiDPI: true,
  displayName: "Virtual Display",
  mirror: false
})

// Read back the requested mode and the mode currently reported by macOS.
// `actualRefreshRate` can be 0 when macOS does not expose a mode refresh rate.
const info = vdisplay.getDisplayInfo()
console.log(info?.requestedRefreshRate, info?.actualRefreshRate)

// To destroy a virtual display:
vdisplay.destroyVirtualDisplay()
```

`createVirtualDisplay` keeps the existing 30–120 Hz range. `frameRate` is
given as a positive integer (e.g. `60`); values outside 30–120 are clamped.
The returned info object includes the virtual display ID, requested
dimensions/rate, current CoreGraphics mode, and online/active state. Rates are
reported exactly as supplied for `create`; for a clone, the actual mode rate is
reported as-is (macOS can expose fractional values such as 59.94, and we do not
round them). The requested rate is not a guarantee that the encoder or the
remote device will deliver that many frames per second; callers should use the
current mode and their transport/decoder metrics when deciding whether a
stream is actually sustaining the target rate.

### API reference

**`createVirtualDisplay(options)` → `DisplayInfo`**

Creates a new virtual display. `options`:

| Option | Type | Default | Notes |
|---|---|---|---|
| `width` | `number` | required | Logical width in pixels (positive integer). |
| `height` | `number` | required | Logical height in pixels (positive integer). |
| `frameRate` | `number` | `60` | Positive integer, clamped to 30–120 Hz. |
| `hiDPI` | `boolean` | `true` | When enabled the physical (backing) resolution is 2x logical and the display is recognised as Retina. |
| `displayName` | `string` | `"Virtual Display"` | Also used as the persistent identity key (see below). |
| `ppi` | `number` | `81` | Positive, clamped to 72–300. |
| `mirror` | `boolean` | `false` | `true` mirrors the main display, `false` extends. |

**`cloneVirtualDisplay(options)` → `DisplayInfo`**

Creates a display matching the main display's resolution and refresh rate.
`options`: `displayName` (default `"Virtual Display"`) and `mirror`
(default `false`).

**`getDisplayInfo()` → `DisplayInfo | null`**

Returns the current display info, or `null` if no display is active.

**`destroyVirtualDisplay()` → `boolean`**

Destroys the virtual display. Returns `true` if a display was destroyed,
`false` if there was nothing to destroy.

**`DisplayInfo`**

```ts
{
  id: number;                 // CoreGraphics display ID
  width: number;              // requested logical width
  height: number;             // requested logical height
  requestedRefreshRate: number;
  actualWidth: number;        // mode reported by macOS (may be 0 pre-settle)
  actualHeight: number;
  actualRefreshRate: number;  // may be 0 when macOS does not expose a rate
  isOnline: boolean;
  isActive: boolean;
}
```

## Persistent Display Identity

This library automatically uses the **Display Name** (`displayName`) as the persistent identity key.

- **Name-Based Persistence**: When you create a display with `displayName: "My Monitor"`, it receives a consistent internal ID derived from that name.
- **Mac Memory**: macOS will remember the window layout and resolution settings associated with that specific name.
- **Simple Usage**: Just use the same name next time, and your windows will be exactly where you left them.

### ⚠️ Note on Changing Resolutions
If you keep the same `displayName` but drastically change the resolution or aspect ratio (e.g., 16:9 -> 4:3), macOS might get confused because it thinks it's the same monitor. If you need a "fresh" monitor profile, simply give it a **new name** (e.g. "Monitor V2").

## Contribute

Coffee fuels coding ☕️
<p align="center">
<a href="https://www.buymeacoffee.com/enfpdev" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
</p>
