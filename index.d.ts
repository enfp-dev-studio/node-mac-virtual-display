// Type definitions for node-mac-virtual-display
// Project: node-mac-virtual-display

export interface DisplayInfo {
  id: number;
  width: number;
  height: number;
  name: string;
}

export interface DisplaySettings {
  width?: number;
  height?: number;
  frameRate?: number;
  hiDPI?: boolean;
}

export interface CreateDisplayOptions {
  width: number;
  height: number;
  frameRate: number;
  hiDPI: boolean;
  displayName: string;
  ppi?: number;
  mirror?: boolean;
}

export interface CloneDisplayOptions {
  displayName: string;
  mirror?: boolean;
}

declare class VirtualDisplayManager {
  constructor();

  /**
   * Creates a new virtual display with the specified options
   * @param options Display creation options
   * @returns Display information if successful, null otherwise
   */
  createVirtualDisplay(options: CreateDisplayOptions): DisplayInfo | null;

  /**
   * Creates a clone of the main display
   * @param options Clone display options
   * @returns Display information if successful, null otherwise
   */
  cloneVirtualDisplay(options: CloneDisplayOptions): DisplayInfo | null;

  /**
   * Destroys a specific virtual display
   * @param displayId The ID of the display to destroy
   * @returns true if successful, false otherwise
   */
  destroyVirtualDisplay(displayId: number): boolean;

  /**
   * Destroys all virtual displays
   * @returns true if all displays were successfully destroyed, false otherwise
   */
  destroyAllDisplays(): boolean;

  /**
   * Gets information about a specific display
   * @param displayId The ID of the display to get information about
   * @returns Display information if found, null otherwise
   */
  getDisplay(displayId: number): DisplayInfo | null;

  /**
   * Gets information about all active virtual displays
   * @returns Array of display information
   */
  getAllDisplays(): DisplayInfo[];

  /**
   * Updates settings for a specific display
   * @param displayId The ID of the display to update
   * @param settings New display settings
   * @returns true if successful, false otherwise
   */
  updateDisplaySettings(displayId: number, settings: DisplaySettings): boolean;
}

export = VirtualDisplayManager;
