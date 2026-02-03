"use strict";

const os = require("os");
const fs = require("fs");
const path = require("path");

function log(message, type = "INFO") {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] [${type}] ${message}`);
}

function checkSystem() {
  log("Starting Diagnostic Check...");
  log(`Platform: ${os.platform()}`);
  log(`Release: ${os.release()}`);
  log(`Arch: ${os.arch()}`);

  if (os.platform() !== "darwin") {
    log("ERROR: This library only supports macOS.", "ERROR");
    process.exit(1);
  }
}

function checkModule() {
  log("Attempting to load node-mac-virtual-display...");
  try {
    const VirtualDisplay = require("..");
    log("Module loaded successfully.");
    return VirtualDisplay;
  } catch (err) {
    log(`Failed to load module: ${err.message}`, "ERROR");
    log("Details:", "ERROR");
    console.error(err);
    return null;
  }
}

function testDisplayCreation(VirtualDisplay) {
  log("Attempting to create a test virtual display...");
  const vdisplay = new VirtualDisplay();

  try {
    // Try to create a 1920x1080 @ 60Hz display
    // Using a random name to avoid potential caching issues (though unlikely)
    const displayConfig = {
      width: 1920,
      height: 1080,
      frameRate: 60,
      hiDPI: true,
      displayName: "Diagnostic Test Display",
      mirror: false,
    };

    log(`Config: ${JSON.stringify(displayConfig)}`);

    const result = vdisplay.createVirtualDisplay(displayConfig);

    if (result && result.id) {
      log(`SUCCESS: Virtual Display created! ID: ${result.id}`, "SUCCESS");
      log(`Width: ${result.width}, Height: ${result.height}`);

      // Destroy it immediately
      log("Destroying test display...");
      vdisplay.destroyVirtualDisplay();
      log("Test display destroyed.");
    } else {
      log(
        "FAILURE: Create call returned but no valid ID/result found.",
        "ERROR",
      );
    }
  } catch (err) {
    log(`EXCEPTION during creation: ${err.message}`, "ERROR");
    console.error(err);
  }
}

(function main() {
  checkSystem();
  const VirtualDisplay = checkModule();
  if (VirtualDisplay) {
    testDisplayCreation(VirtualDisplay);
  } else {
    log("Skipping display creation test due to module load failure.", "WARN");
  }
  log("Diagnostic code finished.");
})();
