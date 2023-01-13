const { expect } = require("chai");
const VirtualDisplay = require("../index");

describe("virtual_display", () => {
  describe("virtual_display", () => {
    it("should not throw", () => {
      expect(() => {
        const vdisplay = new VirtualDisplay();
        vdisplay.createVirtualDisplay();
        setTimeout(() => {
          vdisplay.destroyVirtualDisplay();
        }, 3000);
      }).to.not.throw(/is valid func/);
    });
  });
});
