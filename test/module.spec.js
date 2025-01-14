const { expect } = require("chai");
const VirtualDisplayManager = require("../index");

describe("VirtualDisplayManager", () => {
  let manager;
  let createdDisplays = [];

  beforeEach(() => {
    manager = new VirtualDisplayManager();
    createdDisplays = [];
  });

  afterEach(async () => {
    // Clean up any remaining displays
    await manager.destroyAllDisplays();
  });

  it("should create and destroy a virtual display", () => {
    expect(() => {
      if (manager === null) {
        throw new Error("Manager is null");
      }

      if (manager.createVirtualDisplay) {
        console.log("Manager has createVirtualDisplay method");
      }

      const display = manager.createVirtualDisplay({
        width: 3840,
        height: 2400,
        frameRate: 60,
        hiDPI: true,
        displayName: "Test Display",
        ppi: 266,
        mirror: false,
      });

      console.log("Display:", display);

      expect(display).to.not.be.null;
      expect(display.id).to.be.a("number");
      expect(display.width).to.equal(3840);
      expect(display.height).to.equal(2400);
      createdDisplays.push(display);

      console.log("Created display:", display);

      setTimeout(() => {
        try {
          const success = manager.destroyVirtualDisplay(display.id);
          console.log("Destroyed display:", success);
          expect(success).to.be.true;
        } catch (error) {
          console.error("Error destroying display:", error);
          throw error;
        }
      }, 600000); // 10 minutes
    }).to.not.throw();
  });

  // it("should manage multiple displays", () => {
  //   expect(() => {
  //     // Create first display
  //     const display1 = manager.createVirtualDisplay({
  //       width: 1920,
  //       height: 1080,
  //       frameRate: 60,
  //       hiDPI: true,
  //       displayName: "Test Display 1",
  //       ppi: 96,
  //       mirror: false,
  //     });

  //     // Create second display
  //     const display2 = manager.createVirtualDisplay({
  //       width: 1280,
  //       height: 720,
  //       frameRate: 60,
  //       hiDPI: false,
  //       displayName: "Test Display 2",
  //       ppi: 72,
  //       mirror: false,
  //     });

  //     expect(display1).to.not.be.null;
  //     expect(display2).to.not.be.null;
  //     createdDisplays.push(display1, display2);

  //     // Test getAllDisplays
  //     const allDisplays = manager.getAllDisplays();
  //     expect(allDisplays).to.be.an('array');
  //     expect(allDisplays).to.have.lengthOf(2);

  //     // Test getDisplay
  //     const displayInfo = manager.getDisplay(display1.id);
  //     expect(displayInfo).to.not.be.null;
  //     expect(displayInfo.id).to.equal(display1.id);

  //     console.log("Created displays:", allDisplays);

  //     setTimeout(() => {
  //       try {
  //         const success = manager.destroyAllDisplays();
  //         console.log("Destroyed all displays:", success);
  //         expect(success).to.be.true;
  //       } catch (error) {
  //         console.error("Error destroying displays:", error);
  //         throw error;
  //       }
  //     }, 600000);  // 10 minutes
  //   }).to.not.throw();
  // });

  // it("should clone main display", () => {
  //   expect(() => {
  //     const clonedDisplay = manager.cloneVirtualDisplay({
  //       displayName: "Cloned Display",
  //       mirror: false,
  //     });

  //     expect(clonedDisplay).to.not.be.null;
  //     expect(clonedDisplay.id).to.be.a('number');
  //     createdDisplays.push(clonedDisplay);

  //     console.log("Created cloned display:", clonedDisplay);

  //     setTimeout(() => {
  //       try {
  //         const success = manager.destroyVirtualDisplay(clonedDisplay.id);
  //         console.log("Destroyed cloned display:", success);
  //         expect(success).to.be.true;
  //       } catch (error) {
  //         console.error("Error destroying cloned display:", error);
  //         throw error;
  //       }
  //     }, 600000);  // 10 minutes
  //   }).to.not.throw();
  // });

  // // Optional: Test error cases
  // it("should handle invalid display creation", () => {
  //   const display = manager.createVirtualDisplay({
  //     width: -1,  // Invalid width
  //     height: 1080,
  //     frameRate: 60,
  //     hiDPI: true,
  //     displayName: "Invalid Display",
  //     ppi: 96,
  //     mirror: false,
  //   });

  //   expect(display).to.be.null;
  // });

  // it("should handle destroying non-existent display", () => {
  //   const success = manager.destroyVirtualDisplay(99999);  // Non-existent ID
  //   expect(success).to.be.false;
  // });
});
