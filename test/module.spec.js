const { expect } = require("chai");
const VirtualDisplay = require("..");

/**
 * Integration + unit tests for node-mac-virtual-display.
 *
 * Two layers:
 *   1. JS-layer validation tests are SAFE — they assert input validation
 *      throws before any virtual display is created, so they run on any
 *      platform and never touch the display stack.
 *   2. Integration tests create real virtual displays and therefore require
 *      macOS + Screen Recording permission. Each test tears down its display
 *      in `afterEach` so a failure never leaves an orphaned virtual display.
 */

// Use a distinctive, small, non-HiDPI resolution for the integration display
// so it is cheap to create and unlikely to disturb the user's layout.
const TEST_WIDTH = 1280;
const TEST_HEIGHT = 720;
const TEST_FRAME_RATE = 60;
const TEST_NAME = "Hermes Test Display";

function makeDisplay() {
  return new VirtualDisplay();
}

describe("VirtualDisplay JS-layer validation (no display created)", () => {
  it("throws on non-positive width", () => {
    const vd = makeDisplay();
    expect(() =>
      vd.createVirtualDisplay({ width: 0, height: 720, frameRate: 60 }),
    ).to.throw(/Width must be a positive integer/);
  });

  it("throws on non-integer width", () => {
    const vd = makeDisplay();
    expect(() =>
      vd.createVirtualDisplay({ width: 1280.5, height: 720, frameRate: 60 }),
    ).to.throw(/Width must be a positive integer/);
  });

  it("throws on non-positive height", () => {
    const vd = makeDisplay();
    expect(() =>
      vd.createVirtualDisplay({ width: 1280, height: 0, frameRate: 60 }),
    ).to.throw(/Height must be a positive integer/);
  });

  it("throws on non-positive frame rate", () => {
    const vd = makeDisplay();
    expect(() =>
      vd.createVirtualDisplay({ width: 1280, height: 720, frameRate: 0 }),
    ).to.throw(/Frame rate must be a positive number/);
  });

  it("throws on non-positive PPI", () => {
    const vd = makeDisplay();
    expect(() =>
      vd.createVirtualDisplay({
        width: 1280,
        height: 720,
        frameRate: 60,
        ppi: 0,
      }),
    ).to.throw(/PPI must be a positive number/);
  });

  it("throws when width is not a number", () => {
    const vd = makeDisplay();
    expect(() =>
      vd.createVirtualDisplay({ width: "1280", height: 720, frameRate: 60 }),
    ).to.throw(/Width must be a positive integer/);
  });
});

describe("VirtualDisplay integration (requires macOS virtual display support)", () => {
  let vd;

  beforeEach(() => {
    vd = makeDisplay();
  });

  afterEach(() => {
    // Always tear down so a failed assertion never leaks a virtual display.
    try {
      vd.destroyVirtualDisplay();
    } catch (_err) {
      // ignore cleanup errors in teardown
    }
  });

  it("creates a virtual display and reports the display info", () => {
    const result = vd.createVirtualDisplay({
      width: TEST_WIDTH,
      height: TEST_HEIGHT,
      frameRate: TEST_FRAME_RATE,
      hiDPI: false,
      displayName: TEST_NAME,
      mirror: false,
    });

    expect(result).to.be.an("object");
    expect(result.id).to.be.a("number").that.is.greaterThan(0);
    expect(result.width).to.equal(TEST_WIDTH);
    expect(result.height).to.equal(TEST_HEIGHT);
    expect(result.requestedRefreshRate).to.equal(TEST_FRAME_RATE);
  });

  it("reports actual mode fields via getDisplayInfo", () => {
    vd.createVirtualDisplay({
      width: TEST_WIDTH,
      height: TEST_HEIGHT,
      frameRate: TEST_FRAME_RATE,
      hiDPI: false,
      displayName: TEST_NAME,
      mirror: false,
    });

    const info = vd.getDisplayInfo();
    expect(info).to.be.an("object");
    // The native side should have read back a real mode for the display.
    expect(info.actualWidth).to.be.a("number");
    expect(info.actualHeight).to.be.a("number");
    expect(info.isOnline).to.be.a("boolean");
    expect(info.isActive).to.be.a("boolean");
  });

  it("creates a HiDPI display with physical = 2x logical resolution", () => {
    const result = vd.createVirtualDisplay({
      width: 1920,
      height: 1080,
      frameRate: TEST_FRAME_RATE,
      hiDPI: true,
      displayName: TEST_NAME,
      mirror: false,
    });

    expect(result.width).to.equal(1920);
    expect(result.height).to.equal(1080);
    // Descriptor maxPixels are 2x logical under HiDPI, so the actual mode
    // reported by the system should reflect the physical (backing) size.
    expect(result.actualWidth).to.equal(3840);
    expect(result.actualHeight).to.equal(2160);
  });

  it("returns null from getDisplayInfo after destroy", () => {
    vd.createVirtualDisplay({
      width: TEST_WIDTH,
      height: TEST_HEIGHT,
      frameRate: TEST_FRAME_RATE,
      hiDPI: false,
      displayName: TEST_NAME,
      mirror: false,
    });

    expect(vd.destroyVirtualDisplay()).to.equal(true);
    expect(vd.getDisplayInfo()).to.equal(null);
  });

  it("destroyVirtualDisplay returns false when nothing to destroy", () => {
    expect(vd.destroyVirtualDisplay()).to.equal(false);
  });
});
