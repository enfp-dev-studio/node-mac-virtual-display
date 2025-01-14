"use strict";

const addon = require("bindings")("virtual_display.node");
console.log(require("bindings")("virtual_display.node"));

class VirtualDisplayManager {
  constructor() {
    this._manager = new addon.VDisplayManager();
    this._displays = new Map();
  }

  createVirtualDisplay({
    width,
    height,
    frameRate,
    hiDPI,
    displayName,
    ppi = 81, // FHD Monitor default
    mirror = false,
  }) {
    // console.log(this._manager ? "Manager is not null" : "Manager is null");
    const ret = this._manager.createVirtualDisplay(
      width,
      height,
      frameRate,
      hiDPI,
      displayName,
      ppi,
      mirror
    );

    if (ret) {
      this._displays.set(ret.id, {
        id: ret.id,
        width: ret.width,
        height: ret.height,
        name: displayName,
      });
      return this._displays.get(ret.id);
    }
    return null;
  }

  destroyVirtualDisplay(displayId) {
    const success = this._manager.destroyVirtualDisplay(displayId);
    if (success) {
      this._displays.delete(displayId);
    }
    return success;
  }

  destroyAllDisplays() {
    const displayIds = Array.from(this._displays.keys());
    const results = displayIds.map((id) => this.destroyVirtualDisplay(id));
    return results.every((result) => result === true);
  }

  cloneVirtualDisplay({ displayName, mirror = false }) {
    const ret = this._manager.cloneVirtualDisplay(displayName, mirror);

    if (ret) {
      this._displays.set(ret.id, {
        id: ret.id,
        width: ret.width,
        height: ret.height,
        name: displayName,
      });
      return this._displays.get(ret.id);
    }
    return null;
  }

  getDisplay(displayId) {
    return this._manager.getDisplayByID(displayId);
  }

  getAllDisplays() {
    return this._manager.getAllDisplays();
  }

  updateDisplaySettings(displayId, settings) {
    return this._manager.updateDisplaySettings(displayId, settings);
  }
}

module.exports = VirtualDisplayManager;
