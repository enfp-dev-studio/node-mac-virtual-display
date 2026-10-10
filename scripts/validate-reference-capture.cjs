// Historical pre-simplification experiment; requires the archived restart API.
// Captures and saves only displays created by this process. No personal display
// can be selected. The independent Metal fixture is paced by the display clock.
const assert = require("node:assert/strict");
const { spawn, spawnSync } = require("node:child_process");
const { mkdtemp, writeFile, readFile } = require("node:fs/promises");
const { tmpdir } = require("node:os");
const path = require("node:path");
const { createHash } = require("node:crypto");
const VirtualDisplay = require("..");
const { CaptureSession } = require("./load-capture.cjs").loadCapture();

if (typeof CaptureSession.prototype.requestRestart !== "function") {
  throw new Error(
    "Historical reference experiment requires an archived capture SDK with requestRestart(). The current SDK removed that API; use smoke, throughput or display-mode checks instead.",
  );
}

const cases = {
  "1080p60": { width: 1920, height: 1080, hiDPI: false, fps: 60 },
  "720p120": { width: 1280, height: 720, hiDPI: false, fps: 120 },
  hidpi60: { width: 960, height: 540, hiDPI: true, fps: 60 },
};
const option = (key, fallback) => {
  const value = process.argv.find((argument) =>
    argument.startsWith(`--${key}=`),
  );
  return value ? value.slice(key.length + 3) : fallback;
};
const duration = Number(option("seconds", "6"));
const warmup = Number(option("warmup", "1"));
const minimumFpsRatio = Number(option("minimum-fps-ratio", "0.95"));
const selected = option("cases", Object.keys(cases).join(",")).split(",");
const baselineReference = option("baseline-reference", "");
const patternMode = option("pattern-mode", "metal-display-link");
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const emit = (value) => console.log(JSON.stringify(value));
const command = (binary, args, options = {}) => {
  const result = spawnSync(binary, args, {
    maxBuffer: 64 * 1024 * 1024,
    ...options,
  });
  if (result.error || result.status !== 0) {
    throw new Error(
      `${binary} failed: ${result.error?.message ?? result.stderr?.toString() ?? result.status}`,
    );
  }
  return result.stdout;
};

async function restartAndCheck(capture, previousPtsUs) {
  const started = performance.now();
  return new Promise((resolve, reject) => {
    let recovered;
    const cleanup = () => {
      clearTimeout(timeout);
      capture.off("recovery", onRecovery);
      capture.off("frame", onFrame);
      capture.off("error", onError);
    };
    const onError = (error) => {
      cleanup();
      reject(error);
    };
    const onRecovery = (event) => {
      if (event.type === "recovered") recovered = event;
    };
    const onFrame = (frame) => {
      if (!recovered) return;
      try {
        assert.ok(
          frame.keyFrame,
          "Recovery must begin with an IDR-bearing keyframe",
        );
        assert.ok(
          frame.ptsUs > previousPtsUs,
          "Recovery timestamp did not advance",
        );
        cleanup();
        resolve({
          event: recovered,
          firstFramePtsUs: frame.ptsUs,
          latencyMs: performance.now() - started,
        });
      } catch (error) {
        onError(error);
      }
    };
    const timeout = setTimeout(
      () =>
        onError(
          new Error(
            "Explicit capture restart did not recover within 15 seconds",
          ),
        ),
      15000,
    );
    capture.on("recovery", onRecovery);
    capture.on("frame", onFrame);
    capture.on("error", onError);
    capture.requestRestart();
  });
}

async function patternExecutable(directory) {
  const source = path.resolve(
    __dirname,
    "../native/capture-test-pattern.swift",
  );
  const digest = createHash("sha256")
    .update(await readFile(source))
    .digest("hex")
    .slice(0, 12);
  const executable = path.join(directory, `capture-test-pattern-${digest}`);
  command("xcrun", [
    "swiftc",
    "-swift-version",
    "5",
    "-O",
    "-framework",
    "AppKit",
    "-framework",
    "CoreGraphics",
    "-framework",
    "QuartzCore",
    "-module-cache-path",
    path.join(tmpdir(), "node-vdisplay-pattern-swift-cache"),
    source,
    "-o",
    executable,
  ]);
  return executable;
}

async function baselineExecutable(directory, referenceRoot) {
  const main = path.join(directory, "main.swift");
  await writeFile(
    main,
    await readFile(
      path.resolve(__dirname, "../native/reference-capture-baseline.swift"),
    ),
  );
  const referenceEncoder = path.join(
    referenceRoot,
    "MacHost/Sources/VideoEncoder.swift",
  );
  const original = await readFile(referenceEncoder);
  const executable = path.join(directory, "reference-baseline");
  command("xcrun", [
    "swiftc",
    "-swift-version",
    "5",
    "-O",
    "-framework",
    "AppKit",
    "-framework",
    "ScreenCaptureKit",
    "-framework",
    "VideoToolbox",
    "-framework",
    "CoreMedia",
    "-framework",
    "CoreVideo",
    "-framework",
    "CoreGraphics",
    "-module-cache-path",
    path.join(tmpdir(), "node-vdisplay-pattern-swift-cache"),
    main,
    referenceEncoder,
    "-o",
    executable,
  ]);
  return {
    executable,
    encoderSource: referenceEncoder,
    encoderSha256: createHash("sha256").update(original).digest("hex"),
    referenceCommit: command("git", ["-C", referenceRoot, "rev-parse", "HEAD"])
      .toString()
      .trim(),
  };
}

function startPattern(executable, displayId, width, height, fps, reference) {
  const child = spawn(
    executable,
    [
      String(displayId),
      String(width),
      String(height),
      String(fps),
      reference,
      patternMode,
    ],
    { stdio: ["pipe", "pipe", "pipe"] },
  );
  let buffer = "";
  let diagnostics = "";
  let ready = false;
  let progress;
  const promise = new Promise((resolve, reject) => {
    const timeout = setTimeout(
      () =>
        reject(
          new Error("Test pattern did not become ready within 15 seconds"),
        ),
      15000,
    );
    child.stdout.on("data", (chunk) => {
      buffer += chunk.toString();
      let boundary;
      while ((boundary = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, boundary);
        buffer = buffer.slice(boundary + 1);
        let event;
        try {
          event = JSON.parse(line);
        } catch {
          continue;
        }
        if (event.stage === "ready") {
          ready = true;
          clearTimeout(timeout);
          resolve(event);
        } else if (event.stage === "error") {
          clearTimeout(timeout);
          reject(new Error(event.message));
        } else if (event.stage === "pattern-progress") progress = event;
      }
    });
    child.stderr.on("data", (chunk) => {
      diagnostics += chunk.toString();
    });
    child.on("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    child.on("exit", (code) => {
      clearTimeout(timeout);
      if (!ready)
        reject(new Error(`Test pattern exited ${code}: ${diagnostics}`));
    });
  });
  return { child, promise, progress: () => progress };
}

function qualityMetrics(reference, decoded, width, height) {
  const regions = {
    borders: (x, y) => x < 0.035 || x > 0.965 || y < 0.035 || y > 0.965,
    checker: (x, y) => x >= 0.05 && x <= 0.47 && y >= 0.65 && y <= 0.9,
    text: (x, y) => x >= 0.04 && x <= 0.96 && y >= 0.17 && y <= 0.305,
    colorBars: (x, y) => x >= 0.045 && x <= 0.955 && y >= 0.05 && y <= 0.13,
  };
  const results = {};
  for (const [name, matches] of Object.entries(regions)) {
    let sum = 0;
    let squared = 0;
    let count = 0;
    let inkError = 0;
    let inkPixels = 0;
    const histogram = new Array(256).fill(0);
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        if (!matches(x / width, y / height)) continue;
        const offset = (y * width + x) * 4;
        const luma = (pixels) =>
          pixels[offset] * 0.2126 +
          pixels[offset + 1] * 0.7152 +
          pixels[offset + 2] * 0.0722;
        const expectedLuma = luma(reference);
        const difference = Math.abs(expectedLuma - luma(decoded));
        if (expectedLuma < 128) {
          inkError += difference;
          inkPixels++;
        }
        sum += difference;
        squared += difference * difference;
        histogram[Math.min(255, Math.round(difference))]++;
        count++;
      }
    }
    let cumulative = 0;
    let p95 = 0;
    for (; p95 < 255; p95++) {
      cumulative += histogram[p95];
      if (cumulative >= count * 0.95) break;
    }
    const mse = squared / count;
    results[name] = {
      pixels: count,
      lumaMae: sum / count,
      lumaP95: p95,
      lumaPsnrDb: mse ? 10 * Math.log10((255 * 255) / mse) : 99,
      darkPixelMae: inkPixels ? inkError / inkPixels : 0,
      darkPixels: inkPixels,
    };
  }
  return results;
}

function hevcProfileTierLevel(bytes) {
  for (let offset = 0; offset + 6 < bytes.length; offset++) {
    if (
      bytes.readUInt32BE(offset) !== 1 ||
      ((bytes[offset + 4] >> 1) & 63) !== 33
    )
      continue;
    const rbsp = [];
    let zeroes = 0;
    for (let i = offset + 6; i < bytes.length && rbsp.length < 13; i++) {
      if (zeroes === 2 && bytes[i] === 3) {
        zeroes = 0;
        continue;
      }
      rbsp.push(bytes[i]);
      zeroes = bytes[i] === 0 ? Math.min(zeroes + 1, 2) : 0;
    }
    assert.equal(rbsp.length, 13, "Truncated SPS profile/tier/level");
    return {
      profileSpace: rbsp[1] >> 6,
      profileIdc: rbsp[1] & 31,
      highTier: Boolean(rbsp[1] & 32),
      levelIdc: rbsp[12],
    };
  }
  throw new Error("HEVC stream is missing a length-independent Annex B SPS");
}

async function validateBaseline(name, patternHelper, baseline, directory) {
  const geometry = cases[name];
  const width = geometry.width * (geometry.hiDPI ? 2 : 1);
  const height = geometry.height * (geometry.hiDPI ? 2 : 1);
  const display = new VirtualDisplay();
  let pattern;
  try {
    const info = display.createVirtualDisplay({
      ...geometry,
      frameRate: geometry.fps,
      displayName: `Tab Display SideScreen Baseline ${name}`,
      mirror: false,
    });
    assert.ok(info.isOnline && info.isActive);
    pattern = startPattern(
      patternHelper,
      info.id,
      width,
      height,
      geometry.fps,
      path.join(directory, `${name}-baseline-reference.png`),
    );
    const actualDisplay = await pattern.promise;
    await sleep(300);
    const stream = path.join(directory, `${name}-baseline.h265`);
    const output = command(
      baseline.executable,
      [
        String(info.id),
        String(width),
        String(height),
        String(geometry.fps),
        String(duration),
        String(warmup),
        stream,
      ],
      { timeout: (duration + warmup + 25) * 1000 },
    );
    const events = output
      .toString()
      .split("\n")
      .filter(Boolean)
      .map((line) => JSON.parse(line));
    const metrics = events.find((event) => event.stage === "baseline-result");
    assert.ok(metrics, "Reference baseline did not report real frame counters");
    const decoded = command("ffmpeg", [
      "-v",
      "error",
      "-i",
      stream,
      "-frames:v",
      "1",
      "-f",
      "rawvideo",
      "-pix_fmt",
      "rgba",
      "pipe:1",
    ]);
    const referencePixels = command("ffmpeg", [
      "-v",
      "error",
      "-i",
      path.join(directory, `${name}-baseline-reference.png`),
      "-frames:v",
      "1",
      "-f",
      "rawvideo",
      "-pix_fmt",
      "rgba",
      "pipe:1",
    ]);
    assert.equal(decoded.length, width * height * 4);
    assert.equal(referencePixels.length, decoded.length);
    const result = {
      case: name,
      actualDisplay,
      reference: baseline,
      metrics,
      quality: qualityMetrics(referencePixels, decoded, width, height),
      hevcSps: hevcProfileTierLevel(await readFile(stream)),
      artifacts: { stream },
      limits:
        "Unmodified reference VideoEncoder, matching capture settings and cached-buffer handler; this is a pipeline comparison, not the full SideScreen application.",
    };
    emit({ stage: "baseline-result", ...result });
    await writeFile(
      path.join(directory, `${name}-baseline-result.json`),
      `${JSON.stringify(result, null, 2)}\n`,
    );
    return result;
  } finally {
    if (pattern) {
      pattern.child.stdin.end();
      await Promise.race([
        new Promise((resolve) =>
          pattern.child.exitCode !== null
            ? resolve()
            : pattern.child.once("exit", resolve),
        ),
        sleep(1500),
      ]);
      if (pattern.child.exitCode === null) pattern.child.kill("SIGTERM");
    }
    assert.equal(display.destroyVirtualDisplay(), true);
    assert.equal(
      display.getDisplayInfo(),
      null,
      "Destroyed baseline display is still owned by the addon",
    );
  }
}

async function validateCase(name, executable, directory) {
  const geometry = cases[name];
  const factor = geometry.hiDPI ? 2 : 1;
  const width = geometry.width * factor;
  const height = geometry.height * factor;
  const configuration = {
    width,
    height,
    fps: geometry.fps,
    codec: "h265",
    bitrate: 60000000,
    quality: "ultralow",
  };
  const probe = await CaptureSession.probe(configuration);
  assert.ok(
    probe.supported,
    probe.reason ?? "Reference HEVC settings unsupported",
  );
  assert.ok(probe.permission, "Screen Recording permission is required");
  const display = new VirtualDisplay();
  let pattern;
  let capture;
  const frames = [];
  const chunks = [];
  const nativeStats = [];
  let byteCount = 0;
  let failure;
  let stopped = false;
  let afterStopFrames = 0;
  let ready;
  let patternInfo;
  let measurementStart;
  try {
    const info = display.createVirtualDisplay({
      ...geometry,
      frameRate: geometry.fps,
      displayName: `Tab Display Reference Validation ${name}`,
      mirror: false,
    });
    assert.ok(
      info.isOnline && info.isActive,
      "Own virtual display did not become online/active",
    );
    pattern = startPattern(
      executable,
      info.id,
      width,
      height,
      geometry.fps,
      path.join(directory, `${name}-reference.png`),
    );
    patternInfo = await pattern.promise;
    assert.equal(patternInfo.displayId, info.id);
    assert.equal(patternInfo.physicalWidth, width);
    assert.equal(patternInfo.physicalHeight, height);
    assert.equal(patternInfo.logicalWidth, geometry.width);
    assert.equal(patternInfo.logicalHeight, geometry.height);
    assert.ok(
      Math.abs(patternInfo.actualRefreshRate - geometry.fps) <= 1,
      `Actual display refresh ${patternInfo.actualRefreshRate} differs from requested ${geometry.fps}`,
    );
    assert.equal(
      patternInfo.backingScaleFactor,
      factor,
      "Unexpected HiDPI backing scale",
    );
    await sleep(300);
    capture = new CaptureSession({ ...configuration, displayId: info.id });
    capture.on("stats", (event) => {
      if (nativeStats.length < 60) nativeStats.push(event);
    });
    capture.on("error", (error) => {
      failure ??= error;
    });
    capture.on("frame", (frame) => {
      if (stopped) {
        afterStopFrames++;
        return;
      }
      const wallMs = performance.now();
      frames.push({
        ptsUs: frame.ptsUs,
        wallMs,
        keyFrame: frame.keyFrame,
        codec: frame.codec,
        bytes: frame.data.length,
      });
      byteCount += frame.data.length;
      if (byteCount <= 128 * 1024 * 1024) chunks.push(frame.data);
      else failure ??= new Error("Encoded test stream exceeded 128 MiB bound");
    });
    ready = await capture.start();
    assert.equal(
      ready.quality,
      "ultralow",
      "Ready event does not report the reference quality preset",
    );
    assert.ok(
      ready.encoderTuning.qualityApplied,
      `VT did not apply quality: ${ready.encoderTuning.qualityStatus}`,
    );
    assert.equal(ready.encoderTuning.quality, 0.5);
    await sleep(warmup * 1000);
    assert.ok(frames.length, "No real encoded frame before recovery test");
    const recovery = await restartAndCheck(capture, frames.at(-1).ptsUs);
    // Ignore first-generation compositor bursts after restart when measuring
    // sustained FPS, just as the initial capture has an explicit warmup.
    await sleep(warmup * 1000);
    measurementStart = performance.now();
    await sleep(duration * 1000);
    const measurementEnd = performance.now();
    if (failure) throw failure;
    const measured = frames.filter(
      (frame) =>
        frame.wallMs >= measurementStart && frame.wallMs <= measurementEnd,
    );
    const measuredSeconds = (measurementEnd - measurementStart) / 1000;
    const actualFps = measured.length / measuredSeconds;
    assert.ok(measured.length > 2, "No sustained encoded frame flow");
    for (let i = 1; i < frames.length; i++)
      assert.ok(
        frames[i].ptsUs > frames[i - 1].ptsUs,
        "Frame timestamps did not increase strictly",
      );
    for (const frame of frames) assert.equal(frame.codec, "h265");
    const ptsSeconds = (measured.at(-1).ptsUs - measured[0].ptsUs) / 1000000;
    const ptsFps = (measured.length - 1) / ptsSeconds;
    const gaps = measured
      .slice(1)
      .map((frame, index) => (frame.ptsUs - measured[index].ptsUs) / 1000)
      .sort((a, b) => a - b);
    const keyframeRequested = performance.now();
    const keyframe = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        capture.off("frame", listener);
        reject(new Error("Requested recovery keyframe did not arrive"));
      }, 3000);
      const listener = (frame) => {
        if (frame.keyFrame) {
          clearTimeout(timeout);
          capture.off("frame", listener);
          resolve(frame);
        }
      };
      capture.on("frame", listener);
      capture.requestKeyFrame();
    });
    const keyframeLatencyMs = performance.now() - keyframeRequested;
    assert.ok(keyframe.keyFrame);
    await capture.stop();
    stopped = true;
    await sleep(200);
    assert.equal(afterStopFrames, 0, "Frames arrived after stop completed");
    capture = undefined;
    // Stop while the same real recovery command is being issued. A closed
    // session must not resurrect its stream or deliver buffered late frames.
    capture = new CaptureSession({ ...configuration, displayId: info.id });
    capture.on("error", (error) => {
      failure ??= error;
    });
    let restartStopClosed = false;
    let restartStopLateFrames = 0;
    capture.on("frame", () => {
      if (restartStopClosed) restartStopLateFrames++;
    });
    await capture.start();
    capture.requestRestart();
    await capture.stop();
    restartStopClosed = true;
    await sleep(250);
    assert.equal(
      restartStopLateFrames,
      0,
      "Stopped recovery emitted late frames",
    );
    if (failure) throw failure;
    capture = undefined;
    const stream = path.join(directory, `${name}.h265`);
    const streamBytes = Buffer.concat(chunks);
    await writeFile(stream, streamBytes);
    const sps = hevcProfileTierLevel(streamBytes);
    assert.equal(sps.profileSpace, 0);
    assert.equal(sps.profileIdc, 1, "Android USB requires Main profile");
    assert.equal(sps.highTier, false, "Android USB requires Main tier");
    const encoded = JSON.parse(
      command("ffprobe", [
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=width,height,codec_name,profile,pix_fmt",
        "-of",
        "json",
        stream,
      ]).toString(),
    ).streams[0];
    assert.equal(encoded.codec_name, "hevc");
    assert.equal(encoded.width, width);
    assert.equal(encoded.height, height);
    const decoded = command("ffmpeg", [
      "-v",
      "error",
      "-i",
      stream,
      "-frames:v",
      "1",
      "-f",
      "rawvideo",
      "-pix_fmt",
      "rgba",
      "pipe:1",
    ]);
    const reference = command("ffmpeg", [
      "-v",
      "error",
      "-i",
      path.join(directory, `${name}-reference.png`),
      "-frames:v",
      "1",
      "-f",
      "rawvideo",
      "-pix_fmt",
      "rgba",
      "pipe:1",
    ]);
    assert.equal(decoded.length, width * height * 4);
    assert.equal(reference.length, decoded.length);
    const quality = qualityMetrics(reference, decoded, width, height);
    const latestGeneration = nativeStats.at(-1)?.generation;
    const generationStats = nativeStats.filter(
      (event) => event.generation === latestGeneration,
    );
    const nativeFirst = generationStats[0];
    const nativeLast = generationStats.at(-1);
    const nativeInterval =
      nativeLast && nativeFirst
        ? nativeLast.intervalSeconds - nativeFirst.intervalSeconds
        : 0;
    const nativeSteady =
      nativeInterval > 0
        ? {
            seconds: nativeInterval,
            capturedFps:
              (nativeLast.capturedFrames - nativeFirst.capturedFrames) /
              nativeInterval,
            encodedFps:
              (nativeLast.encodedFrames - nativeFirst.encodedFrames) /
              nativeInterval,
            coalescedFrames:
              nativeLast.coalescedFrames - nativeFirst.coalescedFrames,
            droppedFrames: nativeLast.droppedFrames - nativeFirst.droppedFrames,
            idleCallbacks: nativeLast.idleCallbacks - nativeFirst.idleCallbacks,
            replayedFrames:
              nativeLast.replayedFrames - nativeFirst.replayedFrames,
            replayedFps:
              (nativeLast.replayedFrames - nativeFirst.replayedFrames) /
              nativeInterval,
            meanEncodeMs: nativeLast.meanEncodeMs,
            maxEncodeMs: nativeLast.maxEncodeMs,
          }
        : null;
    const result = {
      case: name,
      requested: configuration,
      actualDisplay: patternInfo,
      encoderReady: ready,
      measurement: {
        seconds: measuredSeconds,
        frames: measured.length,
        actualFps,
        deliveredEncodedFps: actualFps,
        completeCaptureFps: nativeSteady?.capturedFps,
        cachedReplayFps: nativeSteady?.replayedFps,
        ptsFps,
        ptsGapP95Ms: gaps[Math.floor(gaps.length * 0.95)],
        ptsGapMaxMs: gaps.at(-1),
        bitrateMbps:
          (measured.reduce((sum, frame) => sum + frame.bytes, 0) * 8) /
          measuredSeconds /
          1000000,
        keyframes: measured.filter((frame) => frame.keyFrame).length,
        keyframeLatencyMs,
        afterStopFrames,
        recovery,
        stopDuringRestartLateFrames: restartStopLateFrames,
        patternProgress: pattern.progress(),
      },
      decoded: encoded,
      hevcSps: sps,
      nativeStats,
      nativeSteady,
      quality,
      artifacts: {
        stream,
        reference: path.join(directory, `${name}-reference.png`),
      },
    };
    emit({ stage: "case-result", ...result });
    await writeFile(
      path.join(directory, `${name}-result.json`),
      `${JSON.stringify(result, null, 2)}\n`,
    );
    for (const [region, score] of Object.entries(quality)) {
      assert.ok(
        score.lumaMae < 12,
        `${region} decoded luma error ${score.lumaMae.toFixed(2)} exceeds 12; check scaling/geometry/quality`,
      );
      assert.ok(
        score.lumaP95 < 48,
        `${region} decoded luma p95 error ${score.lumaP95} exceeds 48`,
      );
      assert.ok(
        score.darkPixelMae < 40,
        `${region} dark-pixel error ${score.darkPixelMae.toFixed(2)} exceeds 40; missing text/edges must fail`,
      );
    }
    assert.ok(
      nativeSteady,
      "Actual native capture statistics are required for sustained-rate validation",
    );
    assert.ok(
      nativeSteady.capturedFps >= configuration.fps * minimumFpsRatio,
      `Complete-frame capture FPS ${nativeSteady.capturedFps.toFixed(1)} is below the requested ${configuration.fps} FPS tolerance; cached replay cannot satisfy this check`,
    );
    assert.ok(
      actualFps >= configuration.fps * minimumFpsRatio,
      `Delivered encoded FPS ${actualFps.toFixed(1)} is below ${minimumFpsRatio * 100}% of requested ${configuration.fps}`,
    );
    assert.ok(
      ptsFps >= configuration.fps * minimumFpsRatio,
      "PTS frame cadence fell below requested FPS tolerance",
    );
    return result;
  } finally {
    if (capture)
      await capture
        .stop()
        .catch((error) =>
          emit({ stage: "cleanup-error", message: error.message }),
        );
    if (pattern) {
      pattern.child.stdin.end();
      await Promise.race([
        new Promise((resolve) =>
          pattern.child.exitCode !== null
            ? resolve()
            : pattern.child.once("exit", resolve),
        ),
        sleep(1500),
      ]);
      if (pattern.child.exitCode === null) pattern.child.kill("SIGTERM");
    }
    assert.equal(
      display.destroyVirtualDisplay(),
      true,
      "Failed to destroy own test virtual display",
    );
    assert.equal(
      display.getDisplayInfo(),
      null,
      "Destroyed test display is still owned by the addon",
    );
  }
}

async function main() {
  assert.equal(process.platform, "darwin", "Real macOS hardware is required");
  assert.ok(
    duration >= 2 && duration <= 30 && warmup >= 0 && warmup <= 10,
    "Use 2..30 measurement seconds and 0..10 warmup seconds",
  );
  assert.ok(
    minimumFpsRatio >= 0.5 && minimumFpsRatio <= 1,
    "Minimum FPS ratio must be 0.5..1",
  );
  assert.ok(
    ["appkit-buffered", "layer-flush", "metal-display-link"].includes(
      patternMode,
    ),
    "Unknown pattern rendering mode",
  );
  for (const name of selected) assert.ok(cases[name], `Unknown case ${name}`);
  command("ffmpeg", ["-version"]);
  command("ffprobe", ["-version"]);
  const directory = await mkdtemp(
    path.join(tmpdir(), "node-vdisplay-reference-"),
  );
  emit({
    stage: "validation-start",
    directory,
    cases: selected,
    durationSeconds: duration,
    patternMode,
    provenance:
      "Independent AppKit fixture; reference settings inspected in SideScreen 9b0ac6d ScreenCapture.swift/VideoEncoder.swift/StreamTest. No SideScreen performance parity claim.",
  });
  const executable = await patternExecutable(directory);
  const baseline = baselineReference
    ? await baselineExecutable(directory, path.resolve(baselineReference))
    : null;
  const failures = [];
  for (const name of selected) {
    try {
      if (baseline)
        await validateBaseline(name, executable, baseline, directory);
      else await validateCase(name, executable, directory);
      emit({ stage: baseline ? "baseline-recorded" : "case-pass", case: name });
    } catch (error) {
      failures.push({ case: name, message: error.message });
      emit({ stage: "case-fail", case: name, message: error.message });
    }
  }
  emit({
    stage: "validation-complete",
    mode: baseline ? "reference-baseline" : "native-capture",
    ...(baseline
      ? { recorded: selected.length - failures.length }
      : { passed: selected.length - failures.length }),
    total: selected.length,
    failures,
    directory,
    limits: baseline
      ? "Unmodified reference encoder comparison only. The full SideScreen app, physical Android USB, Intel hardware and signed distribution are unverified. Recording a baseline does not mean its requested FPS passed."
      : "Own displays only. Physical Android USB, Intel hardware, signed distribution and full SideScreen application parity are not validated.",
  });
  if (failures.length) process.exitCode = 1;
}
main().catch((error) => {
  console.error(error.stack);
  process.exitCode = 1;
});
