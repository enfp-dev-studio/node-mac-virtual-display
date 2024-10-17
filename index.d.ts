// Type definitions for node-mac-virtual-display
// Project: node-mac-virtual-display

export type DisplayInfo = {
  id: number;
  width: number;
  height: number;
};

export function getDisplayId(): number;
export function createVirtualDisplay({
  width,
  height,
  frameRate,
  hiDPI,
  displayName,
  ppi,
  mirror,
}: {
  width: number;
  height: number;
  frameRate: number;
  hiDPI: boolean;
  displayName: string;
  ppi: number | undefined;
  mirror: boolean;
}): DisplayInfo;
export function cloneVirtualDisplay({
  displayName: string,
  mirror: boolean,
}): DisplayInfo;
export function destroyVirtualDisplay(): boolean;
