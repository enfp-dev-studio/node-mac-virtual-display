"use strict";
const addon = require("bindings")("virtual_display.node");

function VirtualDisplay() {
  this.createVirtualDisplay = function ({ width, height, ppi }) {
    const ret = _addonInstance.createVirtualDisplay(width, height, ppi);
    return {
      id: ret.id,
      width: ret.width,
      height: ret.height,
    };
  };

  this.destroyVirtualDisplay = function () {
    return _addonInstance.destroyVirtualDisplay();
  };

  this.cloneVirtualDisplay = function () {
    const ret = _addonInstance.cloneVirtualDisplay();
    return {
      id: ret.id,
      width: ret.width,
      height: ret.height,
    };
  };

  var _addonInstance = new addon.VDisplay();
}

module.exports = VirtualDisplay;
