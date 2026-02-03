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

// Mock implementation for non-macOS platforms or failures
class MockNativeDisplay implements NativeDisplay {
  createVirtualDisplay(
    width: number,
    height: number,
    frameRate: number,
    hiDPI: boolean,
    displayName: string,
    ppi: number,
    mirror: boolean,
  ): VirtualDisplayInfo {
    console.warn(
      "[VirtualDisplay] Using mock implementation (not on macOS or failed to load)",
    );
    return {
      id: Math.floor(Math.random() * 1000),
      width,
      height,
    };
  }

  cloneVirtualDisplay(
    displayName: string,
    mirror: boolean,
  ): VirtualDisplayInfo {
    console.warn("[VirtualDisplay] Using mock implementation (clone)");
    return {
      id: Math.floor(Math.random() * 1000),
      width: 1920,
      height: 1080,
    };
  }

  destroyVirtualDisplay(): boolean {
    console.warn("[VirtualDisplay] Using mock implementation (destroy)");
    return true;
  }
}

// Load Native Module with standalone support
let addon: { VDisplay: new () => NativeDisplay };
try {
  addon = bindings("virtual_display.node");
} catch (e: any) {
  if (process.platform !== "darwin") {
    addon = { VDisplay: MockNativeDisplay };
  } else {
    throw e;
  }
}

class VirtualDisplay {
  private _addonInstance: NativeDisplay;

  constructor() {
    try {
      this._addonInstance = new addon.VDisplay();
    } catch (e) {
      if (process.platform !== "darwin") {
        this._addonInstance = new MockNativeDisplay();
      } else {
        throw e;
      }
    }
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
