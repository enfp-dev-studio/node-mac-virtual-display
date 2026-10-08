import path from "path";
import nodeGypBuild from "node-gyp-build";

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
  requestedRefreshRate: number;
  actualWidth: number;
  actualHeight: number;
  actualRefreshRate: number;
  isOnline: boolean;
  isActive: boolean;
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
    serial: string,
  ): VirtualDisplayInfo;

  cloneVirtualDisplay(displayName: string, mirror: boolean): VirtualDisplayInfo;

  destroyVirtualDisplay(): boolean;

  getDisplayInfo(): VirtualDisplayInfo | null;
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
    serial: string,
  ): VirtualDisplayInfo {
    console.warn(
      "[VirtualDisplay] Using mock implementation (not on macOS or failed to load)",
    );
    return {
      id: Math.floor(Math.random() * 1000),
      width,
      height,
      requestedRefreshRate: frameRate,
      actualWidth: width,
      actualHeight: height,
      actualRefreshRate: frameRate,
      isOnline: true,
      isActive: true,
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
      requestedRefreshRate: 60,
      actualWidth: 1920,
      actualHeight: 1080,
      actualRefreshRate: 60,
      isOnline: true,
      isActive: true,
    };
  }

  destroyVirtualDisplay(): boolean {
    console.warn("[VirtualDisplay] Using mock implementation (destroy)");
    return true;
  }

  getDisplayInfo(): VirtualDisplayInfo | null {
    console.warn("[VirtualDisplay] Using mock implementation (info)");
    return null;
  }
}

// Load the native addon. node-gyp-build prefers a local build/Release (a dev
// checkout that ran node-gyp) and otherwise picks prebuilds/<platform>-<arch>
// shipped in the npm tarball, so consumers never compile and an x64 process
// never sees an arm64 binary. __dirname is dist/, the package root is one up.
let addon: { VDisplay: new () => NativeDisplay };
try {
  addon = nodeGypBuild(path.join(__dirname, ".."));
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
    // Native descriptors use uint32 physical dimensions. Reserve room for
    // HiDPI's 2x backing size before calling into the display stack.
    const maxDimension = hiDPI ? Math.floor(0xffffffff / 2) : 0xffffffff;
    if (width > maxDimension || height > maxDimension)
      throw new RangeError(
        `Dimensions exceed the ${maxDimension}-pixel limit for ${hiDPI ? "HiDPI" : "standard"} displays`,
      );
    if (!Number.isInteger(frameRate) || frameRate <= 0)
      throw new Error("Frame rate must be a positive integer");
    if (!Number.isFinite(ppi) || ppi <= 0)
      throw new Error("PPI must be a positive number");

    return this._addonInstance.createVirtualDisplay(
      width,
      height,
      frameRate,
      hiDPI,
      displayName,
      ppi,
      mirror,
      displayName, // Use displayName as the serial string for deterministic ID
    );
  }

  cloneVirtualDisplay(options?: {
    displayName?: string;
    mirror?: boolean;
  }): VirtualDisplayInfo {
    const { displayName = "Virtual Display", mirror = false } = options || {};
    // Use displayName directly - "Clone" refers to properties (resolution), not identity
    return this._addonInstance.cloneVirtualDisplay(displayName, mirror);
  }

  destroyVirtualDisplay(): boolean {
    return this._addonInstance.destroyVirtualDisplay();
  }

  getDisplayInfo(): VirtualDisplayInfo | null {
    return this._addonInstance.getDisplayInfo();
  }
}

export = VirtualDisplay;
