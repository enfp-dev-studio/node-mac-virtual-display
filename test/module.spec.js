const { expect } = require("chai");
const path = require("path");
const VirtualDisplay = require("..");

/**
 * Integration + unit tests for node-mac-virtual-display.
 *
 * `npm test` runs JS validation against a guarded native-call boundary and,
 * on macOS, native argument rejection tests. Neither creates a display.
 * `npm run test:integration` explicitly exercises the real macOS display stack.
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

function makeValidationDisplay() {
  const vd = makeDisplay();
  // Guard the boundary so invalid JS input can never create a real display,
  // even if validation regresses. Native rejection cannot mask a JS failure.
  vd._addonInstance = {
    createVirtualDisplay() {
      throw new Error("Invalid JS input reached native display creation");
    },
  };
  return vd;
}

const overflowCases = [
  { hiDPI: true, maxDimension: 2147483647 },
  { hiDPI: false, maxDimension: 4294967295 },
];

describe("VirtualDisplay JS-layer validation (no display created)", () => {
  it("throws on non-positive width", () => {
    const vd = makeValidationDisplay();
    expect(() =>
      vd.createVirtualDisplay({ width: 0, height: 720, frameRate: 60 }),
    ).to.throw(/Width must be a positive integer/);
  });

  it("throws on non-integer width", () => {
    const vd = makeValidationDisplay();
    expect(() =>
      vd.createVirtualDisplay({ width: 1280.5, height: 720, frameRate: 60 }),
    ).to.throw(/Width must be a positive integer/);
  });

  it("throws on non-positive height", () => {
    const vd = makeValidationDisplay();
    expect(() =>
      vd.createVirtualDisplay({ width: 1280, height: 0, frameRate: 60 }),
    ).to.throw(/Height must be a positive integer/);
  });

  it("throws on non-positive frame rate", () => {
    const vd = makeValidationDisplay();
    expect(() =>
      vd.createVirtualDisplay({ width: 1280, height: 720, frameRate: 0 }),
    ).to.throw(/Frame rate must be a positive integer/);
  });

  it("throws on fractional frame rate", () => {
    const vd = makeValidationDisplay();
    expect(() =>
      vd.createVirtualDisplay({ width: 1280, height: 720, frameRate: 59.94 }),
    ).to.throw(/Frame rate must be a positive integer/);
  });

  it("throws on non-positive PPI", () => {
    const vd = makeValidationDisplay();
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
    const vd = makeValidationDisplay();
    expect(() =>
      vd.createVirtualDisplay({ width: "1280", height: 720, frameRate: 60 }),
    ).to.throw(/Width must be a positive integer/);
  });

  for (const { hiDPI, maxDimension } of overflowCases) {
    for (const dimension of ["width", "height"]) {
      it(`rejects overflowing ${dimension} for ${hiDPI ? "HiDPI" : "standard"} displays before native creation`, () => {
        const vd = makeValidationDisplay();
        expect(() =>
          vd.createVirtualDisplay({
            width: TEST_WIDTH,
            height: TEST_HEIGHT,
            hiDPI,
            [dimension]: maxDimension + 1,
          }),
        ).to.throw(
          `Dimensions exceed the ${maxDimension}-pixel limit for ${hiDPI ? "HiDPI" : "standard"} displays`,
        );
      });
    }
  }

  it("applies the HiDPI dimension limit when hiDPI is omitted", () => {
    const vd = makeValidationDisplay();
    expect(() =>
      vd.createVirtualDisplay({ width: 2147483648, height: TEST_HEIGHT }),
    ).to.throw(
      "Dimensions exceed the 2147483647-pixel limit for HiDPI displays",
    );
  });
});

const describeNative = process.platform === "darwin" ? describe : describe.skip;
describeNative(
  "VirtualDisplay native argument validation (no display created)",
  () => {
    let nativeDisplay;

    beforeEach(() => {
      const addon = require("node-gyp-build")(path.join(__dirname, ".."));
      nativeDisplay = new addon.VDisplay();
    });

    afterEach(() => {
      nativeDisplay.destroyVirtualDisplay();
    });

    for (const { hiDPI, maxDimension } of overflowCases) {
      for (const dimension of ["width", "height"]) {
        it(`rejects overflowing ${dimension} for ${hiDPI ? "HiDPI" : "standard"} displays`, () => {
          const dimensions = {
            width: TEST_WIDTH,
            height: TEST_HEIGHT,
            [dimension]: maxDimension + 1,
          };
          expect(() =>
            nativeDisplay.createVirtualDisplay(
              dimensions.width,
              dimensions.height,
              TEST_FRAME_RATE,
              hiDPI,
              TEST_NAME,
              81,
              false,
              TEST_NAME,
            ),
          ).to.throw(/Invalid virtual display dimensions or refresh rate/);
          expect(nativeDisplay.getDisplayInfo()).to.equal(null);
        });
      }
    }
  },
);

describe("VirtualDisplay integration (requires macOS virtual display support)", () => {
  let vd;

  beforeEach(() => {
    vd = makeDisplay();
  });

  afterEach(() => {
    // Always tear down so a failed assertion never leaks a virtual display.
    vd.destroyVirtualDisplay();
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
