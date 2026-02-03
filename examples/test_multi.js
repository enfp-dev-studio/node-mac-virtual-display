const VirtualDisplay = require("..");

console.log("Starting Multiple Display Test...");
const vdisplay1 = new VirtualDisplay();
const vdisplay2 = new VirtualDisplay();

try {
  console.log("Creating Display 1...");
  const d1 = vdisplay1.createVirtualDisplay({
    width: 1920,
    height: 1080,
    frameRate: 60,
    hiDPI: true,
    displayName: "Display One",
    mirror: false,
  });
  console.log(`Display 1 Created: ID ${d1.id}`);

  console.log("Creating Display 2...");
  const d2 = vdisplay2.createVirtualDisplay({
    width: 1280,
    height: 720,
    frameRate: 60,
    hiDPI: false,
    displayName: "Display Two",
    mirror: false,
  });
  console.log(`Display 2 Created: ID ${d2.id}`);

  if (d1.id === d2.id) {
    console.error("FAILURE: IDs are identical!");
    process.exit(1);
  } else {
    console.log("SUCCESS: IDs are unique.");
  }

  console.log("Waiting 3 seconds...");
  setTimeout(() => {
    console.log("Destroying Display 1...");
    vdisplay1.destroyVirtualDisplay();
    console.log("Destroying Display 2...");
    vdisplay2.destroyVirtualDisplay();
    console.log("Test Complete.");
  }, 3000);
} catch (err) {
  console.error("Test Failed with Exception:", err);
  // Try to cleanup
  try {
    vdisplay1.destroyVirtualDisplay();
  } catch (e) {}
  try {
    vdisplay2.destroyVirtualDisplay();
  } catch (e) {}
}
