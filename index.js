"use strict";
const addon = require("bindings")("virtual_display.node");

function VirtualDisplay() {
  this.getDisplayId = () => {
    return _addonInstance.getDisplayId();
  };

  this.createVirtualDisplay = function () {
    return _addonInstance.createVirtualDisplay();
  };

  this.destroyVirtualDisplay = function () {
    return _addonInstance.destroyVirtualDisplay();
  };

  var _addonInstance = new addon.VDisplay();
}

module.exports = VirtualDisplay;
