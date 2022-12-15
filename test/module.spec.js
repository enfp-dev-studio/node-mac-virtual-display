const { expect } = require("chai");
const VirtualDisplay = require("../index");

describe("request-review", () => {
  describe("requestReview()", () => {
    it("should not throw", () => {
      expect(() => {
        const vdisplay = new VirtualDisplay();
        console.log("Virtual Display ID: ", vdisplay.createVirtualDisplay());
      }).to.not.throw(/is valid func/);
    });
  });
});
