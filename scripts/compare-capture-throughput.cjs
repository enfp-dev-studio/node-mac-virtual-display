// Captures only an owned test display. Both paths use the same running source.
const assert = require("node:assert/strict");
const { spawn, spawnSync } = require("node:child_process");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const { createHash } = require("node:crypto");
const VirtualDisplay = require("..");
const { CaptureSession } = require("./load-capture.cjs").loadCapture();

const option = (name, fallback) =>
  process.argv
    .find((x) => x.startsWith(`--${name}=`))
    ?.slice(name.length + 3) ?? fallback;
const seconds = Number(option("seconds", "10"));
const warmup = Number(option("warmup", "2"));
const fps = Number(option("fps", "120"));
const width = Number(option("width", "1280"));
const height = Number(option("height", "720"));
const variant = option("variant", "metal-display-link");
const order = option("order", "reference,native").split(",");
const referenceRoot = option("reference", "/Users/enfpdev/research/SideScreen");
const helperPath = option("helper", "") || undefined;
const referenceInterval = option("reference-interval", "fixed");
const minimumFpsRatio = Number(option("minimum-fps-ratio", "0.95"));
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const emit = (value) => console.log(JSON.stringify(value));
const run = (binary, args, options = {}) => {
  const r = spawnSync(binary, args, {
    maxBuffer: 128 * 1024 * 1024,
    ...options,
  });
  if (r.error || r.status !== 0)
    throw new Error(
      `${binary}: ${r.error?.message ?? r.stderr?.toString() ?? r.status}`,
    );
  return r.stdout;
};

function jsonProcess(executable, args) {
  const child = spawn(executable, args, { stdio: ["pipe", "pipe", "pipe"] });
  const events = [];
  let text = "",
    stderr = "",
    readySent = false,
    readyResolve,
    readyReject;
  const ready = new Promise((resolve, reject) => {
    readyResolve = resolve;
    readyReject = reject;
  });
  ready.catch(() => {});
  const timeout = setTimeout(() => {
    child.kill("SIGKILL");
    readyReject(new Error("Source readiness exceeded 15 seconds"));
  }, 15000);
  child.stdout.on("data", (data) => {
    text += data;
    let end;
    while ((end = text.indexOf("\n")) >= 0) {
      const line = text.slice(0, end);
      text = text.slice(end + 1);
      let event;
      try {
        event = JSON.parse(line);
      } catch {
        continue;
      }
      events.push(event);
      if (["ready", "baseline-ready"].includes(event.stage)) {
        readySent = true;
        clearTimeout(timeout);
        readyResolve(event);
      }
      if (["error", "baseline-error"].includes(event.stage))
        readyReject(new Error(event.message));
    }
  });
  child.stderr.on("data", (data) => {
    stderr = (stderr + data).slice(-32768);
  });
  const closed = new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("close", (code, signal) => {
      clearTimeout(timeout);
      if (!readySent)
        readyReject(
          new Error(`${executable} exited before reporting ready: ${stderr}`),
        );
      if (code === 0) resolve({ events, stderr });
      else {
        const error = new Error(
          `${executable} exited ${code ?? signal}: ${stderr}`,
        );
        readyReject(error);
        reject(error);
      }
    });
  });
  closed.catch(() => {});
  return { child, ready, closed, events };
}

async function compileReference(directory) {
  const main = path.join(directory, "main.swift");
  await fs.copyFile(
    path.resolve(__dirname, "../native/reference-capture-baseline.swift"),
    main,
  );
  const encoder = path.join(
    referenceRoot,
    "MacHost/Sources/VideoEncoder.swift",
  );
  const executable = path.join(directory, "reference-baseline");
  run("xcrun", [
    "swiftc",
    "-swift-version",
    "5",
    "-O",
    "-module-cache-path",
    "/private/tmp/node-vdisplay-pattern-swift-cache",
    main,
    encoder,
    "-o",
    executable,
  ]);
  return {
    executable,
    encoderSha256: createHash("sha256")
      .update(await fs.readFile(encoder))
      .digest("hex"),
    commit: run("git", ["-C", referenceRoot, "rev-parse", "HEAD"])
      .toString()
      .trim(),
  };
}

function decodeMarkers(stream, timeline, duration) {
  // Decode every picture, then align pictures to their corresponding callbacks.
  // Cropping two full-width rows preserves chroma alignment and both anchors.
  const rows = run("ffmpeg", [
    "-v",
    "error",
    "-threads",
    "1",
    "-i",
    stream,
    "-vf",
    `crop=${width}:2:0:48,format=gray`,
    "-vsync",
    "0",
    "-f",
    "rawvideo",
    "pipe:1",
  ]);
  const bytesPerFrame = width * 2;
  assert.equal(rows.length % bytesPerFrame, 0);
  assert.equal(
    rows.length / bytesPerFrame,
    timeline.length,
    "Decoded pictures differ from encoded callback count",
  );
  const epochIds = new Map();
  const ids = [],
    invalid = [];
  timeline.forEach((event, index) => {
    if (!event.measured) return;
    const row = rows.subarray(
      index * bytesPerFrame,
      (index + 1) * bytesPerFrame,
    );
    const white = row[16],
      black = row[width - 16];
    if (white < 180 || black > 70 || white - black < 120) {
      invalid.push(index);
      return;
    }
    const threshold = (white + black) / 2;
    let id = 0;
    for (let bit = 0; bit < 16; bit++)
      if (row[48 + bit * 32] > threshold) id |= 1 << bit;
    ids.push(id);
    const epoch = Math.floor(event.measurementSeconds);
    if (!epochIds.has(epoch)) epochIds.set(epoch, new Set());
    epochIds.get(epoch).add(id);
  });
  const steps = {};
  for (let i = 1; i < ids.length; i++) {
    const step = (ids[i] - ids[i - 1] + 65536) % 65536;
    steps[step] = (steps[step] ?? 0) + 1;
  }
  return {
    decodedPictures: timeline.length,
    measuredPictures: timeline.filter((x) => x.measured).length,
    validMarkers: ids.length,
    invalidMarkers: invalid.length,
    uniqueFrames: new Set(ids).size,
    uniqueFPS: new Set(ids).size / duration,
    frameIdSteps: steps,
    firstFrameIds: ids.slice(0, 32),
    epochs: Array.from({ length: Math.ceil(duration) }, (_, epoch) => ({
      epoch,
      uniqueFrames: epochIds.get(epoch)?.size ?? 0,
    })),
  };
}

async function nativeCapture(displayId, directory, index) {
  const stream = path.join(directory, `${index}-native.h265`);
  const session = new CaptureSession({
    displayId,
    width,
    height,
    fps,
    codec: "h265",
    bitrate: 60_000_000,
    quality: "ultralow",
    helperPath,
  });
  const chunks = [],
    timeline = [],
    stats = [],
    errors = [];
  let start = Infinity,
    end = Infinity,
    bytes = 0,
    afterStop = 0,
    stopped = false;
  session.on("error", (error) =>
    errors.push({ code: error.code, message: error.message }),
  );
  session.on("stats", (event) => stats.push(event));
  session.on("frame", (frame) => {
    if (stopped) {
      afterStop++;
      return;
    }
    const now = performance.now();
    bytes += frame.data.length;
    if (bytes > 256 * 1024 * 1024) {
      errors.push({ message: "Encoded stream exceeded 256 MiB bound" });
      return;
    }
    chunks.push(frame.data);
    timeline.push({
      measured: now >= start && now < end,
      measurementSeconds: Number.isFinite(start) ? (now - start) / 1000 : null,
      wallMs: now,
      ptsUs: frame.ptsUs,
      keyFrame: frame.keyFrame,
    });
  });
  let ready;
  try {
    ready = await session.start();
    await sleep(warmup * 1000);
    start = performance.now();
    end = start + seconds * 1000;
    await sleep(seconds * 1000);
    const actualEnd = performance.now();
    await session.stop();
    stopped = true;
    if (errors.length) throw new Error(JSON.stringify(errors));
    await fs.writeFile(stream, Buffer.concat(chunks));
    await fs.writeFile(
      path.join(directory, `${index}-native-timeline.json`),
      JSON.stringify(timeline),
    );
    const decoded = decodeMarkers(stream, timeline, seconds);
    for (let i = 1; i < timeline.length; i++)
      assert.ok(
        timeline[i].ptsUs > timeline[i - 1].ptsUs,
        "Native timestamps must increase",
      );
    return {
      path: "native",
      ready,
      seconds,
      timerElapsedSeconds: (actualEnd - start) / 1000,
      measuredEncodedFPS: decoded.measuredPictures / seconds,
      decoded,
      stats,
      afterStop,
      stream,
    };
  } finally {
    await session.stop().catch(() => {});
  }
}

async function referenceCapture(displayId, directory, index, reference) {
  const stream = path.join(directory, `${index}-reference.h265`);
  const timelinePath = path.join(directory, `${index}-reference-timeline.json`);
  const process = jsonProcess(
    reference.executable,
    [
      displayId,
      width,
      height,
      fps,
      seconds,
      warmup,
      stream,
      timelinePath,
      referenceInterval,
    ].map(String),
  );
  const deadline = setTimeout(
    () => process.child.kill("SIGKILL"),
    (seconds + warmup + 20) * 1000,
  );
  try {
    const output = await process.closed;
    const result = output.events.findLast((x) => x.stage === "baseline-result");
    assert.ok(result, "Reference did not report a result");
    const timeline = JSON.parse(await fs.readFile(timelinePath));
    return {
      path: "reference",
      reference,
      seconds,
      measuredEncodedFPS: result.encodedFps,
      decoded: decodeMarkers(stream, timeline, seconds),
      stats: result,
      diagnostics: output.stderr,
      stream,
    };
  } finally {
    clearTimeout(deadline);
    if (process.child.exitCode === null) {
      process.child.kill("SIGKILL");
      await process.closed.catch(() => {});
    }
  }
}

async function main() {
  assert.ok(seconds >= 2 && seconds <= 30 && warmup >= 0 && warmup <= 10);
  assert.ok(
    fps >= 1 &&
      fps <= 240 &&
      width >= 576 &&
      height >= 240 &&
      width % 2 === 0 &&
      height % 2 === 0,
  );
  assert.ok(order.every((x) => ["native", "reference"].includes(x)));
  assert.ok(["fixed", "native"].includes(referenceInterval));
  assert.ok(minimumFpsRatio >= 0.85 && minimumFpsRatio <= 1);
  const directory = await fs.mkdtemp(
    path.join(os.tmpdir(), "node-vdisplay-throughput-"),
  );
  emit({
    stage: "start",
    directory,
    width,
    height,
    fps,
    seconds,
    warmup,
    variant,
    order,
  });
  const reference = order.includes("reference")
    ? await compileReference(directory)
    : null;
  const display = new VirtualDisplay();
  let source;
  const cases = [];
  let sourceInfo;
  try {
    const info = display.createVirtualDisplay({
      width,
      height,
      frameRate: fps,
      hiDPI: false,
      mirror: false,
      displayName: "Tab Display Throughput Comparison",
    });
    assert.ok(info.isOnline && info.isActive);
    source = jsonProcess(
      option("pattern", "/private/tmp/node-vdisplay-cadence-metal"),
      [info.id, width, height, fps, variant].map(String),
    );
    sourceInfo = await source.ready;
    assert.equal(sourceInfo.displayId, info.id);
    assert.equal(sourceInfo.actualRefreshRate, fps);
    for (const [index, implementation] of order.entries()) {
      assert.equal(
        source.child.exitCode,
        null,
        "Source stopped before measurement",
      );
      const result =
        implementation === "native"
          ? await nativeCapture(info.id, directory, index)
          : await referenceCapture(info.id, directory, index, reference);
      assert.equal(
        source.child.exitCode,
        null,
        "Source stopped during measurement",
      );
      result.performancePassed =
        result.decoded.invalidMarkers === 0 &&
        result.decoded.uniqueFPS >= fps * minimumFpsRatio;
      cases.push(result);
      await fs.writeFile(
        path.join(directory, `${index}-${implementation}-result.json`),
        JSON.stringify(result, null, 2) + "\n",
      );
      emit({
        stage: "case-result",
        path: implementation,
        index,
        encodedFPS: result.measuredEncodedFPS,
        uniqueFPS: result.decoded.uniqueFPS,
        invalidMarkers: result.decoded.invalidMarkers,
      });
      await sleep(300);
    }
  } finally {
    try {
      if (source) {
        source.child.stdin.end();
        const kill = setTimeout(() => source.child.kill("SIGKILL"), 4000);
        try {
          await source.closed;
        } finally {
          clearTimeout(kill);
        }
      }
    } finally {
      assert.equal(display.destroyVirtualDisplay(), true);
    }
  }
  const report = {
    timestamp: new Date().toISOString(),
    width,
    height,
    fps,
    seconds,
    warmup,
    variant,
    source: sourceInfo,
    sourceProgress: source.events,
    cases,
    reference,
    referenceInterval,
    minimumFpsRatio,
    nativePerformancePassed: cases
      .filter((x) => x.path === "native")
      .every((x) => x.performancePassed),
    limits:
      "One owned display and one continuously running source; sequential component comparison, not the full SideScreen app or physical USB. Encoded unique images verified by frame marker; complete and replay statistics kept separate.",
  };
  await fs.writeFile(
    path.join(directory, "report.json"),
    JSON.stringify(report, null, 2) + "\n",
  );
  emit({ stage: "complete", directory, cases: cases.length });
  if (cases.some((x) => x.path === "native" && !x.performancePassed))
    process.exitCode = 1;
}
main().catch((error) => {
  console.error(error.stack);
  process.exitCode = 1;
});
