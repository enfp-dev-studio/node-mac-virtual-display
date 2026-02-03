import path from "path";
import bindings from "bindings";

// Type definitions
interface VirtualDisplayOptions {
  width: number;
  height: number;
  frameRate?: number;
  hiDPI?: boolean;
  displayName?: string;
  ppi?: number;
  mirror?: boolean;
}

interface VirtualDisplayInfo {
  id: number;
  width: number;
  height: number;
}

interface NativeDisplay {
  createVirtualDisplay(
    width: number,
    height: number,
    frameRate: number,
    hiDPI: boolean,
    displayName: string,
    ppi: number,
    mirror: boolean,
  ): VirtualDisplayInfo;

  cloneVirtualDisplay(displayName: string, mirror: boolean): VirtualDisplayInfo;

  destroyVirtualDisplay(): boolean;
}

// Load Native Module with standalone support
let addon: { VDisplay: new () => NativeDisplay };
try {
  addon = bindings("virtual_display.node");
} catch (e: any) {
  // Fallback for pkg/standalone: look in executable directory
  try {
    addon = require(path.join(
      path.dirname(process.execPath),
      "virtual_display.node",
    ));
  } catch (e2) {
    throw e;
  }
}

class VirtualDisplay {
  private _addonInstance: NativeDisplay;

  constructor() {
    this._addonInstance = new addon.VDisplay();
  }

  createVirtualDisplay(options: VirtualDisplayOptions): VirtualDisplayInfo {
    const {
      width,
      height,
      frameRate = 60,
      hiDPI = true,
      displayName = "Virtual Display",
      ppi = 81, // Default to FHD Monitor PPI
      mirror = false,
    } = options;

    // Additional Javascript-side validation
    if (!Number.isInteger(width) || width <= 0)
      throw new Error("Width must be a positive integer");
    if (!Number.isInteger(height) || height <= 0)
      throw new Error("Height must be a positive integer");

    return this._addonInstance.createVirtualDisplay(
      width,
      height,
      frameRate,
      hiDPI,
      displayName,
      ppi,
      mirror,
    );
  }

  cloneVirtualDisplay(options: {
    displayName?: string;
    mirror?: boolean;
  }): VirtualDisplayInfo {
    const { displayName = "Virtual Display", mirror = false } = options || {};
    return this._addonInstance.cloneVirtualDisplay(displayName, mirror);
  }

  destroyVirtualDisplay(): boolean {
    return this._addonInstance.destroyVirtualDisplay();
  }
}

export = VirtualDisplay;
