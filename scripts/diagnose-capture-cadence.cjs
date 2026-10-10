// Raw capture experiment on owned virtual displays. No encoder or USB is used.
const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const { mkdtemp, writeFile } = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const VirtualDisplay = require("..");

const argument = (name, fallback) =>
  process.argv
    .find((value) => value.startsWith(`--${name}=`))
    ?.slice(name.length + 3) ?? fallback;
const seconds = Number(argument("seconds", "4"));
const warmup = Number(argument("warmup", "1"));
const patternHelper = argument(
  "pattern",
  "/private/tmp/node-vdisplay-cadence-pattern",
);
const probeHelper = argument("probe", "/private/tmp/capture-cadence-probe");
const suite = {
  default120: {},
  flush120: { variant: "timer-window-flush" },
  layer120: { variant: "timer-layer-flush" },
  layerDefault120: { variant: "timer-layer-default" },
  transactionFlush120: { variant: "timer-transaction-flush" },
  layerNativeInterval120: { variant: "timer-layer-flush", captureFps: 0 },
  layerRelaxedInterval120: { variant: "timer-layer-flush", captureFps: 240 },
  layerRenderer240: { variant: "timer-layer-flush", rendererFps: 240 },
  displayLink120: { variant: "display-link" },
  heavy120: { variant: "timer-heavy" },
  bgra120: { pixelFormat: "bgra" },
  nativeInterval120: { captureFps: 0 },
  relaxedInterval120: { captureFps: 240 },
  window120: { scope: "window" },
  cgStream120: { backend: "cgdisplaystream", pixelFormat: "bgra" },
  display60: { displayFps: 60 },
  display90: { displayFps: 90 },
  capture60: { captureFps: 60 },
  metal120: { renderer: "metal", variant: "metal-vsync" },
  metalNoVsync120: { renderer: "metal", variant: "metal-no-vsync" },
  metalDisplayLink120: { renderer: "metal", variant: "metal-display-link" },
  metalDisplayLinkNative120: {
    renderer: "metal",
    variant: "metal-display-link",
    captureFps: 0,
  },
  metalDisplayLinkBGRA120: {
    renderer: "metal",
    variant: "metal-display-link",
    pixelFormat: "bgra",
  },
  metalNativeInterval120: {
    renderer: "metal",
    variant: "metal-vsync",
    captureFps: 0,
  },
  metalRelaxedInterval120: {
    renderer: "metal",
    variant: "metal-vsync",
    captureFps: 240,
  },
  metalRenderer240: {
    renderer: "metal",
    variant: "metal-vsync",
    rendererFps: 240,
  },
  metalStatusOnly120: {
    renderer: "metal",
    variant: "metal-vsync",
    decodeMarker: false,
  },
  defaultStatusOnly120: { decodeMarker: false },
};
const selected = argument("cases", Object.keys(suite).join(",")).split(",");

function jsonChild(executable, args) {
  const child = spawn(executable, args, { stdio: ["pipe", "pipe", "pipe"] });
  let stdout = "";
  let stderr = "";
  const events = [];
  let readyResolve;
  let readyReject;
  const ready = new Promise((resolve, reject) => {
    readyResolve = resolve;
    readyReject = reject;
  });
  ready.catch(() => {});
  const deadline = setTimeout(() => {
    child.kill("SIGKILL");
    readyReject(new Error(`${executable} readiness exceeded 15 seconds`));
  }, 15000);
  child.stdout.on("data", (chunk) => {
    stdout += chunk.toString();
    let end;
    while ((end = stdout.indexOf("\n")) >= 0) {
      const line = stdout.slice(0, end);
      stdout = stdout.slice(end + 1);
      try {
        const event = JSON.parse(line);
        events.push(event);
        if (event.stage === "ready") {
          clearTimeout(deadline);
          readyResolve(event);
        }
        if (event.stage === "error") {
          clearTimeout(deadline);
          readyReject(new Error(event.message));
        }
      } catch (error) {
        if (error instanceof SyntaxError) stderr += `Invalid event: ${line}\n`;
        else readyReject(error);
      }
    }
  });
  child.stderr.on("data", (chunk) => {
    stderr = (stderr + chunk.toString()).slice(-32768);
  });
  const closed = new Promise((resolve, reject) => {
    child.once("error", (error) => {
      clearTimeout(deadline);
      readyReject(error);
      reject(error);
    });
    child.once("close", (code, signal) => {
      clearTimeout(deadline);
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

async function stopPattern(pattern) {
  if (!pattern) return;
  pattern.child.stdin.end();
  const kill = setTimeout(() => pattern.child.kill("SIGKILL"), 3000);
  try {
    await pattern.closed;
  } finally {
    clearTimeout(kill);
  }
}

async function runCase(name, directory) {
  assert.ok(Object.hasOwn(suite, name), `Unknown case ${name}`);
  const config = {
    width: 1280,
    height: 720,
    displayFps: 120,
    rendererFps: 120,
    captureFps: 120,
    variant: "timer-default",
    pixelFormat: "nv12",
    scope: "display",
    backend: "sck",
    decodeMarker: true,
    ...suite[name],
  };
  const display = new VirtualDisplay();
  let pattern;
  let probe;
  const startedAt = new Date().toISOString();
  try {
    const info = display.createVirtualDisplay({
      width: config.width,
      height: config.height,
      frameRate: config.displayFps,
      hiDPI: false,
      mirror: false,
      displayName: `Tab Display Cadence ${name}`,
    });
    assert.ok(info.isOnline && info.isActive);
    pattern = jsonChild(
      config.renderer === "metal"
        ? argument("metal", "/private/tmp/node-vdisplay-cadence-metal")
        : patternHelper,
      [
        String(info.id),
        String(config.width),
        String(config.height),
        String(config.rendererFps),
        config.variant,
      ],
    );
    const source = await pattern.ready;
    assert.equal(source.displayId, info.id);
    const args = [
      "--display-id",
      String(info.id),
      "--width",
      String(config.width),
      "--height",
      String(config.height),
      "--fps",
      String(config.captureFps),
      "--duration",
      String(seconds),
      "--warmup",
      String(warmup),
      "--pixel-format",
      config.pixelFormat,
      "--scope",
      config.scope,
      "--backend",
      config.backend,
      "--color-mode",
      "reference",
      "--queue-depth",
      "4",
      "--marker-x",
      "48",
      "--marker-y",
      "48",
      "--marker-cell",
      "32",
    ];
    if (config.scope === "window")
      args.push("--window-id", String(source.windowId));
    if (!config.decodeMarker) args.push("--decode-marker", "false");
    probe = jsonChild(probeHelper, args);
    const kill = setTimeout(
      () => probe.child.kill("SIGKILL"),
      (seconds + warmup + 20) * 1000,
    );
    let measured;
    try {
      measured = await probe.closed;
    } finally {
      clearTimeout(kill);
    }
    const result = measured.events.findLast(
      (event) => event.stage === "result",
    );
    assert.ok(result, "Raw capture probe did not report a result");
    const sourceExitBeforeStop = {
      exitCode: pattern.child.exitCode,
      signalCode: pattern.child.signalCode,
    };
    let sourceOutcome;
    try {
      await stopPattern(pattern);
      sourceOutcome = {
        exitCode: pattern.child.exitCode,
        ...(await pattern.closed),
      };
    } catch (error) {
      sourceOutcome = {
        exitCode: pattern.child.exitCode,
        signalCode: pattern.child.signalCode,
        error: error.message,
      };
    }
    const report = {
      case: name,
      startedAt,
      configuration: config,
      source,
      patternProgress: pattern.events.filter(
        (event) => event.stage !== "ready",
      ),
      sourceExitBeforeStop,
      sourceOutcome,
      capture: result,
      probeEvents: measured.events.filter((event) => event.stage !== "result"),
      diagnostics: measured.stderr,
    };
    await writeFile(
      path.join(directory, `${name}.json`),
      JSON.stringify(report, null, 2) + "\n",
    );
    assert.equal(
      sourceExitBeforeStop.exitCode,
      null,
      "Pattern exited during measurement",
    );
    assert.equal(
      sourceExitBeforeStop.signalCode,
      null,
      "Pattern was terminated during measurement",
    );
    assert.ok(!sourceOutcome.error, sourceOutcome.error);
    console.log(
      JSON.stringify({
        stage: "case-result",
        case: name,
        sourceHz: source.actualRefreshRate,
        sourceMaximumFPS: source.maximumFramesPerSecond,
        completeFPS: result.completeFPS,
        uniqueFPS: result.uniqueFPS,
        callbackFPS: result.callbackFPS,
        invalidMarkers: result.invalidMarkers,
        statuses: result.statuses,
        sourceError: sourceOutcome.error,
        cvDisplayLink: result.cvDisplayLink,
      }),
    );
    return report;
  } finally {
    if (probe && probe.child.exitCode === null) {
      probe.child.kill("SIGKILL");
      await probe.closed.catch(() => {});
    }
    await stopPattern(pattern).catch((error) => console.error(error.message));
    display.destroyVirtualDisplay();
  }
}

async function main() {
  assert.ok(seconds >= 2 && seconds <= 30 && warmup >= 0 && warmup <= 10);
  const directory = await mkdtemp(
    path.join(os.tmpdir(), "node-vdisplay-cadence-"),
  );
  console.log(
    JSON.stringify({ stage: "start", directory, selected, seconds, warmup }),
  );
  const cases = [];
  for (const name of selected) {
    try {
      cases.push(await runCase(name, directory));
    } catch (error) {
      cases.push({ case: name, error: error.message });
      console.log(
        JSON.stringify({
          stage: "case-error",
          case: name,
          message: error.message,
        }),
      );
      process.exitCode = 1;
    }
  }
  const report = {
    timestamp: new Date().toISOString(),
    platform: process.platform,
    architecture: process.arch,
    seconds,
    warmup,
    cases,
  };
  await writeFile(
    path.join(directory, "report.json"),
    JSON.stringify(report, null, 2) + "\n",
  );
  console.log(
    JSON.stringify({
      stage: "complete",
      directory,
      errors: cases.filter((item) => item.error).length,
    }),
  );
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
