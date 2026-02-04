#!/bin/bash
set -e

# Directory setup
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."
BUILD_DIR="$ROOT_DIR/_build_temp"
DIST_DIR="$ROOT_DIR/dist-app"
EXAMPLE_DIR="$ROOT_DIR/examples/electron"

echo "🧹 Cleaning up..."
rm -rf "$BUILD_DIR"
rm -rf "$DIST_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$DIST_DIR"

# 1. Pack the current project
echo "📦 Packing root project..."
cd "$ROOT_DIR"
PACK_FILENAME=$(npm pack | tail -n 1) # Captures the filename output by npm pack
PACK_PATH="$ROOT_DIR/$PACK_FILENAME"

if [ ! -f "$PACK_PATH" ]; then
    echo "❌ Failed to create tarball"
    exit 1
fi

echo "✅ Packed to $PACK_PATH"

# 2. Prepare the app workspace
echo "📂 Preparing app workspace..."
cp -r "$EXAMPLE_DIR/"* "$BUILD_DIR/"
cd "$BUILD_DIR"

# 3. Create package.json for the app
# We explicitly depend on the tarball we just created to ensure the native module is built correctly for this app
cat > package.json <<EOF
{
  "name": "virtual-display-test-app",
  "version": "0.0.1",
  "main": "main.js",
  "description": "Test app for node-mac-virtual-display",
  "scripts": {
    "start": "electron ."
  },
  "dependencies": {
    "node-mac-virtual-display": "file:$PACK_PATH"
  },
  "devDependencies": {
    "electron": "^40.1.0",
    "electron-packager": "^17.1.2"
  }
}
EOF

# 4. Modify main.js to import the package by name instead of relative path
# Assuming the line is set to: const VirtualDisplay = require("../..");
echo "🔧 Patching main.js..."
sed -i '' 's|require("\.\./\.\.")|require("node-mac-virtual-display")|g' main.js

# 5. Install dependencies
echo "⬇️ Installing dependencies..."
npm install

# 6. Build the app
echo "🔨 Packaging application..."
# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" == "x86_64" ]; then
  ARCH="x64"
else
  ARCH="arm64"
fi

echo "   Target Arch: $ARCH"

# Pack it
npx electron-packager . "VirtualDisplayTest" \
  --platform=darwin \
  --arch=$ARCH \
  --out="$DIST_DIR" \
  --overwrite \
  --icon="$ROOT_DIR/examples/assets/icon.icns" || true 
  # (ignoring icon error if assets don't exist)

echo "✨ Done! App located in $DIST_DIR"
open "$DIST_DIR"
