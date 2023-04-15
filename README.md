# node-mac-virtual-display: Native Library for Virtual Display on macOS

A native library for macOS to create virtual displays for your applications using Node.js. This library uses CoreGraphics and CoreDisplay APIs to provide an interface for creating and managing virtual displays on macOS.

## Features

- [x] Create and Destroy single virtual displays on macOS.
- [x] Configurable display resolution and refresh rate.
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

// To create a virtual display:
vdisplay.createVirtualDisplay({
  width: 1920,
  height: 1080,
  frameRate: 60,
  hiDPI: true,
})

//To destroy a virtual display:
vdisplay.destroyVirtualDisplay()

```

## Contribute

Coffee fuels coding ☕️
<p align="center">
<a href="https://www.buymeacoffee.com/enfpdev" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
</p>
