const { expect } = require("chai");
const VirtualDisplay = require("../index");

describe("virtual_display", () => {
  it("should not throw", () => {
    expect(() => {
      const vdisplay = new VirtualDisplay();
      const result = vdisplay.createVirtualDisplay({
        width: 2800,
        height: 1752,
        frameRate: 60,
        hiDPI: false,
        displayName: "Test Display",
        ppi: 340,
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
      // try {
      //   const ret = vdisplay.cloneVirtualDisplay({
      //     displayName: "Clone Display",
      //   });
      //   console.log("destroy: ", ret);
      // } catch (error) {
      //   console.log(error);
      // }
      // setTimeout(() => {
      //   try {
      //     const ret = vdisplay.destroyVirtualDisplay();
      //     console.log("destroy: ", ret);
      //   } catch (error) {
      //     console.log(error);
      //   }
      // }, 600000);
    }).to.not.throw(/is valid func/);
  });
});
