"use strict";
const addon = require("bindings")("virtual_display.node");

function VirtualDisplay() {
  this.createVirtualDisplay = function ({
    width,
    height,
    frameRate,
    hiDPI,
    ppi,
  }) {
    const ret = _addonInstance.createVirtualDisplay(
      width,
      height,
      frameRate,
      hiDPI ? hiDPI : 1,
      ppi ? ppi : 0
    );
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
