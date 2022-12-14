"use strict";
const { VDisplay } = require("bindings")("virtual_display.node");

// const addon = require('../build/Release/object-wrap-demo-native');

function VirtualDisplay(name) {
  const _addonInstance = new VDisplay();

  this.getDisplayId = function () {
    return _addonInstance.displayId;
  };

  this.createVDisplay = () => {
    return _addonInstance.createVirtualDisplay;
  };
  // return _addonInstance;
}

// const vdisplay = new VirtualDisplay();
// vdisplay.createVDisplay();

// const vdisplay = new VDisplay();
// console.log(vdisplay.displayId);

module.exports = VirtualDisplay;
