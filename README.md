# node-mac-virtual-display: Native Library for Virtual Display on macOS

A native library for macOS to create virtual displays for your applications using Node.js. This library uses CoreGraphics and CoreDisplay APIs to provide an interface for creating and managing virtual displays on macOS. This library is used in [Tab Display](https://tab-display.enfpdev.com), a service that allows iPads and Android tablets to be used as portable monitors.

## Features

- [x] Create and Destroy single virtual displays on macOS.
- [x] Configurable display resolution and refresh rate.
- [x] Create a virtual display by cloning the main display.
- [x] Added option to select between Mirror and Extend display modes
- [ ] Support for multiple virtual displays.

## Requirements

- macOS 10.14 or later
- Node.js 12 or later

## Installation

Use npm to install the library:

```shell
yarn add node-mac-virtual-display
```
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

//To destroy a virtual display:
vdisplay.destroyVirtualDisplay()
```

## Persistent Display Identity

This library now automatically uses the **Display Name** (`displayName`) as the persistent identity key.

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
