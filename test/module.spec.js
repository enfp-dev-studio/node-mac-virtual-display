const { expect } = require("chai");
const VirtualDisplay = require("../index");

describe("virtual_display", () => {
  it("should not throw", () => {
    expect(() => {
      const vdisplay = new VirtualDisplay();
      const result = vdisplay.createVirtualDisplay({
        width: 2800,
        height: 1752,
        frameRate: 30,
        hiDPI: true,
        // ppi: 340,
      });
      console.log(result);
      setTimeout(() => {
        try {
          const ret = vdisplay.destroyVirtualDisplay();
          console.log("destroy: ", ret);
        } catch (error) {
          console.log(error);
        }
      }, 2000);
      setTimeout(() => {
        try {
          const ret = vdisplay.cloneVirtualDisplay();
          console.log("destroy: ", ret);
        } catch (error) {
          console.log(error);
        }
      }, 4000);
      setTimeout(() => {
        try {
          const ret = vdisplay.destroyVirtualDisplay();
          console.log("destroy: ", ret);
        } catch (error) {
          console.log(error);
        }
      }, 6000);
    }).to.not.throw(/is valid func/);
  });
});
