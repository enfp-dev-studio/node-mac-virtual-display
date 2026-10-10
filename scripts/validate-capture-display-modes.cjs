// Hardware regression: switches only the display owned by the diagnostic fixture.
const assert = require("node:assert/strict");
const { spawn, spawnSync } = require("node:child_process");
const { writeFile } = require("node:fs/promises");
const { CaptureSession } = require("./load-capture.cjs").loadCapture();
const option = (name, fallback) =>
  process.argv
    .find((x) => x.startsWith(`--${name}=`))
    ?.slice(name.length + 3) ?? fallback;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function jsonProcess(executable, args) {
  const child = spawn(executable, args, { stdio: ["pipe", "pipe", "pipe"] });
  const events = [];
  let buffer = "",
    diagnostics = "";
  child.stdout.on("data", (chunk) => {
    buffer += chunk;
    let end;
    while ((end = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, end);
      buffer = buffer.slice(end + 1);
      try {
        events.push(JSON.parse(line));
      } catch {}
    }
  });
  child.stderr.on("data", (chunk) => {
    diagnostics = (diagnostics + chunk).slice(-32768);
  });
  child.on("error", (error) =>
    events.push({ stage: "error", message: error.message }),
  );
  const closed = new Promise((resolve) => child.once("close", resolve));
  return { child, events, closed, diagnostics: () => diagnostics };
}

async function waitFor(check, message) {
  const deadline = performance.now() + 15000;
  while (performance.now() < deadline) {
    const result = check();
    if (result) return result;
    await sleep(20);
  }
  throw new Error(message);
}

function eventFrom(process, stage, since = 0) {
  const error = process.events.find((x) => x.stage === "error");
  if (error) throw new Error(error.message);
  if (process.child.exitCode !== null)
    throw new Error(
      `Diagnostic process exited ${process.child.exitCode}: ${process.diagnostics()}`,
    );
  return process.events.slice(since).find((x) => x.stage === stage);
}

async function main() {
  const fixture = jsonProcess(
    option("fixture", "/private/tmp/node-vdisplay-mode-fixture"),
    ["--initial-hz", "60"],
  );
  let source, session, report;
  const frames = [],
    recoveries = [],
    errors = [],
    phases = [];
  let stopped = false,
    afterStopFrames = 0;
  try {
    const owned = await waitFor(
      () => eventFrom(fixture, "ready"),
      "Owned multi-mode display did not become ready",
    );
    assert.notEqual(
      owned.displayId,
      owned.mainDisplayId,
      "Fixture must own a secondary display",
    );
    assert.equal(owned.actualRefreshRate, 60);
    source = jsonProcess(
      option("pattern", "/private/tmp/node-vdisplay-cadence-metal"),
      [String(owned.displayId), "1280", "720", "120", "metal-display-link"],
    );
    await waitFor(
      () => eventFrom(source, "ready"),
      "Display-clock source did not become ready",
    );
    session = new CaptureSession({
      displayId: owned.displayId,
      width: 1280,
      height: 720,
      fps: 60,
      codec: "h265",
      bitrate: 60000000,
      quality: "ultralow",
    });
    session.on("error", (error) =>
      errors.push({ code: error.code, message: error.message }),
    );
    session.on("recovery", (event) => recoveries.push(event));
    session.on("frame", (frame) => {
      if (stopped) {
        afterStopFrames++;
        return;
      }
      frames.push({
        ptsUs: frame.ptsUs,
        keyFrame: frame.keyFrame,
        wallMs: performance.now(),
        recoveryCount: recoveries.filter((x) => x.type === "recovered").length,
      });
    });
    const ready = await session.start();
    assert.equal(
      ready.captureTuning.minimumFrameIntervalMode,
      "native-refresh",
    );
    for (const [index, hz] of [60, 120, 60, 120, 60].entries()) {
      let tuning = ready.captureTuning;
      if (index) {
        const previousPts = frames.at(-1).ptsUs;
        const eventStart = recoveries.length;
        const fixtureStart = fixture.events.length;
        fixture.child.stdin.write(`mode ${hz}\n`);
        const ack = await waitFor(
          () => eventFrom(fixture, "mode", fixtureStart),
          "Owned display did not acknowledge mode change",
        );
        assert.equal(ack.actualRefreshRate, hz);
        const recovery = await waitFor(
          () =>
            recoveries.slice(eventStart).find((x) => x.type === "recovered"),
          `Capture did not recover after mode ${hz}`,
        );
        assert.equal(recovery.reason, "DISPLAY_MODE_CHANGED");
        tuning = recovery.captureTuning;
        const first = await waitFor(
          () =>
            frames.find(
              (x) => x.ptsUs > previousPts && x.recoveryCount === index,
            ),
          "No frame after mode recovery",
        );
        assert.ok(
          first.keyFrame,
          "A changed display mode must resume with a keyframe",
        );
      }
      assert.equal(tuning.displayRefreshRate, hz);
      assert.equal(tuning.requestedFPS, 60);
      assert.equal(
        tuning.minimumFrameIntervalMode,
        hz === 60 ? "native-refresh" : "fixed",
      );
      await sleep(600);
      const start = performance.now();
      await sleep(1500);
      const end = performance.now();
      const measured = frames.filter(
        (x) => x.wallMs >= start && x.wallMs < end,
      );
      const encodedFPS = measured.length / ((end - start) / 1000);
      assert.ok(
        encodedFPS > 30 && encodedFPS <= 63,
        `Selected 60 FPS ceiling violated: ${encodedFPS}`,
      );
      assert.equal(errors.length, 0, JSON.stringify(errors));
      assert.equal(source.child.exitCode, null);
      phases.push({ displayHz: hz, tuning, encodedFPS });
    }
    assert.equal(recoveries.filter((x) => x.type === "recovered").length, 4);
    for (let i = 1; i < frames.length; i++)
      assert.ok(frames[i].ptsUs > frames[i - 1].ptsUs);
    await session.stop();
    stopped = true;
    await sleep(300);
    assert.equal(afterStopFrames, 0);
    report = {
      timestamp: new Date().toISOString(),
      owned,
      selectedFPS: 60,
      ready,
      phases,
      recoveries,
      frames: frames.length,
      afterStopFrames,
      errors,
      passed: true,
    };
  } catch (error) {
    console.error(
      JSON.stringify({
        stage: "failure",
        message: error.message,
        phases,
        recoveries,
        errors,
        fixtureEvents: fixture.events,
        sourceEvents: source?.events.slice(-2),
        frames: frames.length,
      }),
    );
    throw error;
  } finally {
    await session?.stop().catch(() => {});
    for (const process of [source, fixture]) {
      if (!process) continue;
      process.child.stdin.end();
      const kill = setTimeout(() => process.child.kill("SIGKILL"), 4000);
      await process.closed;
      clearTimeout(kill);
    }
  }
  assert.equal(source.child.exitCode, 0, "Source cleanup failed");
  assert.equal(fixture.child.exitCode, 0, "Owned display cleanup failed");
  const removed = fixture.events.findLast((x) => x.stage === "stopped");
  assert.ok(removed);
  assert.equal(removed.mainDisplayId, removed.originalMainDisplayId);
  const verification = spawnSync(
    option("fixture", "/private/tmp/node-vdisplay-mode-fixture"),
    [
      "--assert-offline",
      String(removed.displayId),
      "--assert-main",
      String(removed.originalMainDisplayId),
    ],
    { timeout: 5000, encoding: "utf8" },
  );
  assert.equal(
    verification.status,
    0,
    verification.stderr || verification.stdout,
  );
  const cleanup = JSON.parse(verification.stdout.trim());
  assert.equal(cleanup.passed, true);
  assert.equal(cleanup.online, false);
  report.cleanup = {
    beforeProcessExit: removed,
    independentlyVerifiedAfterExit: cleanup,
  };
  await writeFile(
    option("output", "/private/tmp/node-vdisplay-display-modes.json"),
    JSON.stringify(report, null, 2) + "\n",
  );
  console.log(JSON.stringify(report));
}
main().catch((error) => {
  console.error(error.stack);
  process.exitCode = 1;
});
