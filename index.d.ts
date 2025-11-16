// Type definitions for node-mac-virtual-display
// Project: node-mac-virtual-display

export type DisplayInfo = {
  id: number;
  width: number;
  height: number;
};

export class VirtualDisplay {
  constructor();

  createVirtualDisplay(options: {
    width: number;
    height: number;
    frameRate: number;
    hiDPI: boolean;
    displayName: string;
    ppi?: number;
    mirror: boolean;
  }): DisplayInfo;

  cloneVirtualDisplay(options: {
    displayName: string;
    mirror: boolean;
  }): DisplayInfo;

  destroyVirtualDisplay(): boolean;
}
