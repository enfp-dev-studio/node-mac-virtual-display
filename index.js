"use strict";
const addon = require("bindings")("virtual_display.node");

function VirtualDisplay() {
  this.createVirtualDisplay = function ({ width, height, ppi }) {
    return _addonInstance.createVirtualDisplay(width, height, ppi);
  };

  this.destroyVirtualDisplay = function () {
    return _addonInstance.destroyVirtualDisplay();
  };

  var _addonInstance = new addon.VDisplay();
}

module.exports = VirtualDisplay;
