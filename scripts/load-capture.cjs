const path = require("node:path");

function resolveCaptureEntry({ argv = process.argv, env = process.env } = {}) {
  const argument = argv.find((value) => value.startsWith("--capture-library="));
  const library = argument?.slice("--capture-library=".length);
  const override = env.TAB_DISPLAY_NATIVE_CAPTURE_MODULE;
  if (argument && (!library || !path.isAbsolute(library))) {
    throw new Error(
      "--capture-library must be an absolute capture checkout path",
    );
  }
  if (override && !path.isAbsolute(override)) {
    throw new Error(
      "TAB_DISPLAY_NATIVE_CAPTURE_MODULE must be an absolute module path",
    );
  }
  const entry = library && path.resolve(library, "dist/index.js");
  if (entry && override && path.resolve(override) !== entry) {
    throw new Error(
      "--capture-library conflicts with TAB_DISPLAY_NATIVE_CAPTURE_MODULE",
    );
  }
  if (!entry && !override) {
    throw new Error(
      "Select the independent capture checkout with --capture-library=/absolute/path/node-mac-screen-capture or set TAB_DISPLAY_NATIVE_CAPTURE_MODULE to its absolute dist/index.js path",
    );
  }
  return override || entry;
}

function loadCapture(options) {
  return require(resolveCaptureEntry(options));
}

module.exports = { resolveCaptureEntry, loadCapture };
