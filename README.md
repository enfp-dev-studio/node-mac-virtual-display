# node-mac-virtual-display: Native Library for Virtual Display on macOS

A native library for macOS to create virtual displays for your applications using Node.js. This library uses CoreGraphics and CoreDisplay APIs to provide an interface for creating and managing virtual displays on macOS.

## Note

This module was created specifically for Tab Display to generate virtual displays. Tab Display can seamlessly transform your Android tablet into a wireless external display for your MacBook. If you're enjoying this library, we recommend giving Tab Display a try as well.

<br />
 <p align="center">
  <a href="https://tab-display.enfpdev.com" target="_blank"><img width="196" alt="image" src="https://user-images.githubusercontent.com/57121116/224042438-ce511784-28fd-42b8-b90a-bb01230983c0.png"></a>
</p>



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
vdisplay.createVirtualDisplay()

//To destroy a virtual display:
vdisplay.destroyVirtualDisplay()

```
## Contribute

Coffee fuels coding ☕️
<p align="center">
<a href="https://www.buymeacoffee.com/enfpdev" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
</p>
