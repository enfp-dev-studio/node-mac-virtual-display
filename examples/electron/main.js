const { app, BrowserWindow, ipcMain } = require("electron");
const path = require("path");
const VirtualDisplay = require("../.."); // Load from root

let mainWindow;
let vdisplay;
let displayInstance;

// Initialize VirtualDisplay
try {
  vdisplay = new VirtualDisplay();
} catch (error) {
  console.error("Failed to initialize Virtual Display module:", error);
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 600,
    height: 600,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
    },
  });

  mainWindow.loadFile("index.html");
}

app.whenReady().then(() => {
  createWindow();

  app.on("activate", function () {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", function () {
  if (process.platform !== "darwin") app.quit();
});

app.on("will-quit", () => {
  if (vdisplay && displayInstance) {
    console.log("Destroying Virtual Display...");
    vdisplay.destroyVirtualDisplay();
  }
});

// IPC Handlers
ipcMain.handle("create-display", async (event, options) => {
  if (!vdisplay) throw new Error("VirtualDisplay not initialized");
  if (displayInstance) {
    return { success: false, error: "Display already exists" };
  }

  try {
    console.log("Creating display with options:", options);
    displayInstance = vdisplay.createVirtualDisplay(options);
    console.log("Created:", displayInstance);
    return { success: true, id: displayInstance.id };
  } catch (err) {
    console.error(err);
    return { success: false, error: err.message };
  }
});

ipcMain.handle("destroy-display", async () => {
  if (!vdisplay) throw new Error("VirtualDisplay not initialized");
  if (!displayInstance) {
    return { success: false, error: "No display to destroy" };
  }

  try {
    console.log("Destroying display...");
    vdisplay.destroyVirtualDisplay();
    displayInstance = null;
    return { success: true };
  } catch (err) {
    console.error(err);
    return { success: false, error: err.message };
  }
});

ipcMain.handle("open-settings", async () => {
  try {
    const { shell } = require("electron");
    await shell.openPath("/System/Library/PreferencePanes/Displays.prefPane");
    return { success: true };
  } catch (err) {
    console.error(err);
    return { success: false, error: err.message };
  }
});

ipcMain.handle("clone-display", async (event, options) => {
  if (!vdisplay) throw new Error("VirtualDisplay not initialized");
  // Clone logic in C++ might require cleanup of existing display first, or not.
  // Based on reading: `CloneVirtualDisplay` cleans up existing display if any.
  // So we don't need to manually destroy.

  try {
    console.log("Cloning display...");
    displayInstance = vdisplay.cloneVirtualDisplay(options || {});
    console.log("Cloned:", displayInstance);
    return { success: true, id: displayInstance.id };
  } catch (err) {
    console.error(err);
    return { success: false, error: err.message };
  }
});
