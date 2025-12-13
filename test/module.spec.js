const { expect } = require("chai");
const VirtualDisplay = require("../index");

describe("virtual_display", () => {
  it("should not throw", () => {
    expect(() => {
      const vdisplay = new VirtualDisplay();
      // CASE 1: Create a new virtual display
      const result = vdisplay.createVirtualDisplay({
        width: 3840,
        height: 2400,
        frameRate: 60,
        hiDPI: true,
        displayName: "Test Display",
        ppi: 266,
        mirror: false,
      });
      console.log(result);
      setTimeout(() => {
        try {
          const ret = vdisplay.destroyVirtualDisplay();
          console.log("destroy: ", ret);
        } catch (error) {
          console.log(error);
        }
      }, 600000);
      // CASE 2: Clone the existing display
      const result2 = vdisplay.cloneVirtualDisplay({
        displayName: "Clone Display",
        mirror: false,
      });
      console.log(result2);
      setTimeout(() => {
        try {
          const ret = vdisplay.destroyVirtualDisplay();
          console.log("destroy: ", ret);
        } catch (error) {
          console.log(error);
        }
      }, 600000);
    }).to.not.throw(/is valid func/);
  });
});
