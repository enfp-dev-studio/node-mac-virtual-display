// Type definitions for node-mac-virtual-display
// Project: node-mac-virtual-display

export function getDisplayId(): number;
export function createVirtualDisplay({
  width,
  height,
  ppi,
}: {
  width: number;
  height: number;
  ppi: number;
}): number;
export function destroyVirtualDisplay(): boolean;
