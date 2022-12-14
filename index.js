"use strict";
const { VDisplay } = require("bindings")("virtual_display.node");

// const addon = require('../build/Release/object-wrap-demo-native');

function VirtualDisplay(name) {
  this.getDisplayId = function () {
    return _addonInstance.displayId;
  };

  this.createVDisplay = _addonInstance.CreateVDisplay;
  var _addonInstance = new VDisplay();
  return _addonInstance;
}

// const vdisplay = new VDisplay();
// console.log(vdisplay.displayId);

module.exports = VirtualDisplay;
