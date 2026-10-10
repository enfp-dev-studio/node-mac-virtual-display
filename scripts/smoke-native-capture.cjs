// Captures only a newly created test virtual display; no images are saved.
const assert = require("node:assert/strict");
const { once } = require("node:events");
const VirtualDisplay = require("..");
const { CaptureSession } = require("./load-capture.cjs").loadCapture();

async function main() {
  const codec = process.argv.includes("--h264") ? "h264" : "h265";
  const config = { width: 640, height: 360, fps: 60, codec, bitrate: 8000000 };
  const capability = await CaptureSession.probe(config);
  console.log(JSON.stringify({ stage: "probe", ...capability }));
  if (!capability.supported)
    throw new Error(
      capability.reason ?? "Hardware encoder configuration is unsupported",
    );
  if (!capability.permission) {
    throw new Error(
      "Screen Recording permission is required for the native capture helper. Enable it in macOS System Settings, then rerun this smoke test.",
    );
  }
  const display = new VirtualDisplay();
  let capture;
  try {
    const info = display.createVirtualDisplay({
      width: 640,
      height: 360,
      hiDPI: false,
      frameRate: 60,
      displayName: "Tab Display Native Capture Smoke",
      mirror: false,
    });
    capture = new CaptureSession({ ...config, displayId: info.id });
    capture.on("error", (error) =>
      console.error(
        JSON.stringify({
          stage: "capture-error",
          code: error.code,
          message: error.message,
        }),
      ),
    );
    const firstFrame = once(capture, "frame");
    // Attach the rejection handler before start so failures cannot leak an
    // unhandled events.once rejection while startup itself is pending.
    firstFrame.catch(() => {});
    const ready = await capture.start();
    const timeout = setTimeout(
      () =>
        capture.emit(
          "error",
          new Error("No encoded frame within 5 seconds of readiness"),
        ),
      5000,
    );
    let frame;
    try {
      [frame] = await firstFrame;
    } finally {
      clearTimeout(timeout);
    }
    assert.equal(frame.codec, codec);
    assert.equal(frame.keyFrame, true);
    const nalTypes = [];
    for (let i = 0; i + 4 < frame.data.length; i++) {
      if (frame.data.readUInt32BE(i) === 1) {
        nalTypes.push(
          codec === "h265"
            ? (frame.data[i + 4] >> 1) & 63
            : frame.data[i + 4] & 31,
        );
      }
    }
    for (const type of codec === "h265" ? [32, 33, 34] : [7, 8])
      assert.ok(
        nalTypes.includes(type),
        `Keyframe is missing parameter-set NAL ${type}`,
      );
    assert.ok(
      nalTypes.some((type) =>
        codec === "h265"
          ? type === 19 || type === 20 || type === 21
          : type === 5,
      ),
      "Keyframe has no random-access picture",
    );
    console.log(
      JSON.stringify({
        stage: "encoded-frame",
        ready,
        bytes: frame.data.length,
        ptsUs: frame.ptsUs,
        keyFrame: frame.keyFrame,
        nalTypes,
      }),
    );
    // A static display may emit no more complete SCK frames. Recovery still
    // needs a keyframe, so exercise replay of the retained native pixel buffer.
    const recovery = await new Promise((resolve, reject) => {
      const cleanup = () => {
        clearTimeout(timer);
        capture.off("frame", onFrame);
        capture.off("error", onError);
      };
      const onError = (error) => {
        cleanup();
        reject(error);
      };
      const onFrame = (next) => {
        // Frames already in flight may arrive before the command reaches VT.
        if (!next.keyFrame || next.ptsUs <= frame.ptsUs) return;
        cleanup();
        resolve(next);
      };
      const timer = setTimeout(
        () => onError(new Error("Idle-display keyframe request timed out")),
        5000,
      );
      capture.on("frame", onFrame);
      capture.once("error", onError);
      capture.requestKeyFrame();
    });
    console.log(
      JSON.stringify({
        stage: "keyframe-recovery",
        bytes: recovery.data.length,
        ptsUs: recovery.ptsUs,
      }),
    );
    await capture.stop();
    capture = undefined;
  } finally {
    if (capture)
      await capture
        .stop()
        .catch((error) => console.error(`Cleanup: ${error.message}`));
    display.destroyVirtualDisplay();
  }
}
main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
