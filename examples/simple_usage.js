const VirtualDisplay = require("..");

// Create a virtual display
// 1920x1080 @ 60Hz, HiDPI enabled
console.log("Creating Virtual Display...");
const vdisplay = new VirtualDisplay();

try {
  const display = vdisplay.createVirtualDisplay({
    width: 1920,
    height: 1080,
    frameRate: 60,
    hiDPI: true,
    displayName: "My Virtual Monitor",
    mirror: false,
  });

  console.log(`Display Created!`);
  console.log(`ID: ${display.id}`);
  console.log(`Resolution: ${display.width}x${display.height}`);

  // Keep it alive for 5 seconds
  console.log("Waiting 5 seconds...");
  setTimeout(() => {
    console.log("Destroying Display...");
    vdisplay.destroyVirtualDisplay();
    console.log("Done.");
  }, 5000);
} catch (err) {
  console.error("Failed to create display:", err.message);
}
