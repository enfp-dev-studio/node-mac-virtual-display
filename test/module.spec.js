const { expect } = require("chai");
const VirtualDisplay = require("../index");

describe("virtual_display", () => {
  describe("virtual_display", () => {
    it("should not throw", () => {
      expect(() => {
        const vdisplay = new VirtualDisplay();
        vdisplay.createVirtualDisplay();
        setTimeout(() => {
          try {
            const ret = vdisplay.destroyVirtualDisplay();
            console.log("destroy: ", ret);
          } catch (error) {
            console.log(error);
          }
        }, 3000);
        setTimeout(() => {
          try {
            const ret = vdisplay.createVirtualDisplay();
            console.log("destroy: ", ret);
          } catch (error) {
            console.log(error);
          }
        }, 6000);
      }).to.not.throw(/is valid func/);
    });
  });
});
