const { expect } = require("chai");
const VirtualDisplay = require("../index");

describe("virtual_display", () => {
  it("should not throw", () => {
    expect(() => {
      const vdisplay = new VirtualDisplay();
      // const result = vdisplay.createVirtualDisplay({
      //   width: 1920,
      //   height: 1080,
      //   frameRate: 60,
      //   hiDPI: true,
      // });
      // console.log(result);
      // setTimeout(() => {
      //   try {
      //     const ret = vdisplay.destroyVirtualDisplay();
      //     console.log("destroy: ", ret);
      //   } catch (error) {
      //     console.log(error);
      //   }
      // }, 2000);
      setTimeout(() => {
        try {
          const ret = vdisplay.cloneVirtualDisplay();
          console.log("destroy: ", ret);
        } catch (error) {
          console.log(error);
        }
      }, 1000);
      setTimeout(() => {
        try {
          const ret = vdisplay.destroyVirtualDisplay();
          console.log("destroy: ", ret);
        } catch (error) {
          console.log(error);
        }
      }, 120000);
    }).to.not.throw(/is valid func/);
  });
});
