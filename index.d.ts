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
}: {
  width: number;
  height: number;
}): DisplayInfo;
export function cloneVirtualDisplay(): DisplayInfo;
export function destroyVirtualDisplay(): boolean;
