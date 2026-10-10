#!/usr/bin/env node
// Source-checkout packaging check. Loading exports creates no displays/capture.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const sourceManifest = require("../package.json");
assert.equal(
  process.platform,
  "darwin",
  "Package binary validation requires macOS",
);
assert.equal(
  process.argv.length,
  3,
  "Usage: node scripts/validate-package.cjs <tarball>",
);
const tarball = path.resolve(process.argv[2]);
const run = (file, args, cwd) =>
  execFileSync(file, args, { cwd, encoding: "utf8", timeout: 120000 });
const contents = run("tar", ["-tf", tarball])
  .trim()
  .split("\n")
  .filter((entry) => !entry.endsWith("/"))
  .map((entry) => {
    assert.ok(
      entry.startsWith("package/"),
      `Unexpected tarball entry: ${entry}`,
    );
    const file = entry.slice("package/".length);
    assert.ok(
      !file.split("/").includes(".."),
      `Unsafe tarball entry: ${entry}`,
    );
    return file;
  });
const allowed = ["package.json", ...sourceManifest.files];
for (const file of contents) {
  assert.ok(
    allowed.some((entry) =>
      entry.endsWith("/") ? file.startsWith(entry) : file === entry,
    ),
    `Unexpected file in runtime package: ${file}`,
  );
  if (file.startsWith("prebuilds/")) {
    assert.match(
      file,
      /^prebuilds\/darwin-(arm64|x64)\/[^/]+\.node$/,
      `Only macOS native addons belong in prebuilds: ${file}`,
    );
  }
}
for (const file of [
  "dist/index.js",
  "dist/index.d.ts",
  "src/index.ts",
  "src/node-gyp-build.d.ts",
  "src/noop.cc",
  "src/virtual_display.mm",
  "binding.gyp",
  "LICENSE",
  "THIRD_PARTY_NOTICES.md",
]) {
  assert.ok(
    contents.includes(file),
    `Required package file is missing: ${file}`,
  );
}
assert.ok(
  !contents.some(
    (file) =>
      /^(capture\.|capture-prebuilds\/|native\/|packages\/|docs\/)/.test(
        file,
      ) ||
      file.startsWith("dist/capture.") ||
      file === "src/capture.ts",
  ),
  "The virtual-display artifact must exclude capture and diagnostics",
);

const temporary = fs.mkdtempSync(
  path.join(os.tmpdir(), "node-vdisplay-package-"),
);
try {
  fs.writeFileSync(
    path.join(temporary, "package.json"),
    JSON.stringify({ private: true }),
  );
  // Ignore lifecycle scripts to prove prebuild consumption needs no compilation.
  run(
    "npm",
    [
      "install",
      "--ignore-scripts",
      "--omit=dev",
      "--no-audit",
      "--no-fund",
      "--package-lock=false",
      "--prefer-offline",
      "--cache",
      path.join(temporary, ".npm-cache"),
      tarball,
    ],
    temporary,
  );
  const installed = path.join(temporary, "node_modules", sourceManifest.name);
  const manifest = JSON.parse(
    fs.readFileSync(path.join(installed, "package.json"), "utf8"),
  );
  assert.equal(manifest.version, sourceManifest.version);
  const architectures = [];
  for (const [arch, machine] of [
    ["arm64", "arm64"],
    ["x64", "x86_64"],
  ]) {
    const addonDirectory = path.join(installed, "prebuilds", `darwin-${arch}`);
    const addons = fs
      .readdirSync(addonDirectory)
      .filter((file) => file.endsWith(".node"));
    assert.equal(addons.length, 1, `Expected one addon for ${arch}`);
    const addon = path.join(addonDirectory, addons[0]);
    assert.equal(run("lipo", ["-archs", addon]).trim(), machine);
    architectures.push(arch);
  }
  run(
    process.execPath,
    [
      "-e",
      `
    const assert = require('node:assert/strict');
    assert.throws(() => require.resolve('node-mac-virtual-display/capture'), {code: 'MODULE_NOT_FOUND'});
    assert.throws(() => require.resolve('@enfp-dev-studio/node-mac-screen-capture'), {code: 'MODULE_NOT_FOUND'});
    assert.equal(typeof require('node-mac-virtual-display'), 'function');
  `,
    ],
    temporary,
  );
  console.log(
    JSON.stringify(
      {
        version: manifest.version,
        tarball,
        files: contents.length,
        architectures,
        cleanInstall: true,
        hostArchitecture: process.arch,
        defaultEntryLoaded: true,
        captureExcluded: true,
        diagnosticsExcluded: true,
      },
      null,
      2,
    ),
  );
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
