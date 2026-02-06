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

# --- 1. Pack the current project ---
echo "📦 Packing root project..."
cd "$ROOT_DIR"
PACK_FILENAME=$(npm pack | tail -n 1) # Captures the filename output by npm pack
PACK_PATH="$ROOT_DIR/$PACK_FILENAME"

if [ ! -f "$PACK_PATH" ]; then
    echo "❌ Failed to create tarball"
    exit 1
fi

echo "✅ Packed to $PACK_PATH"

# --- 2. Prepare the app workspace ---
echo "📂 Preparing app workspace..."
cp -r "$EXAMPLE_DIR/"* "$BUILD_DIR/"
cd "$BUILD_DIR"

# --- 3. Create package.json for the app ---
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
    "electron-packager": "^17.1.2",
    "@electron/osx-sign": "^1.3.1"
  }
}
EOF

# --- 4. Patch main.js ---
echo "🔧 Patching main.js..."
sed -i '' 's|require("\.\./\.\.")|require("node-mac-virtual-display")|g' main.js

# --- 5. Install dependencies ---
echo "⬇️ Installing dependencies..."
npm install

# --- 6. Build the app (and Sign) ---
echo "🔨 Packaging application..."
# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" == "x86_64" ]; then
  ARCH="x64"
else
  ARCH="arm64"
fi
echo "   Target Arch: $ARCH"

# Find Signing Identity
SIGNING_IDENTITY=""
if security find-identity -v -p codesigning | grep "Developer ID Application" > /dev/null; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n 1 | awk -F '"' '{print $2}')
    echo "🔐 Found Signing Identity: $SIGNING_IDENTITY"
else
    echo "⚠️ No Developer ID Application certificate found. Building UNSIGNED."
fi

# Build arguments
PACKAGER_ARGS=( "." "VirtualDisplayTest" --platform=darwin --arch=$ARCH --out="$DIST_DIR" --overwrite )

# Add signing if identity found
if [ -n "$SIGNING_IDENTITY" ]; then
    PACKAGER_ARGS+=( "--osx-sign" "--osx-sign.identity=$SIGNING_IDENTITY" "--osx-sign.hardened-runtime=false" )
fi

# Add icon if exists
ICON_PATH="$ROOT_DIR/examples/assets/icon.icns"
if [ -f "$ICON_PATH" ]; then
    PACKAGER_ARGS+=( "--icon=$ICON_PATH" )
fi

# Run Packager
echo "   Running electron-packager..."
npx electron-packager "${PACKAGER_ARGS[@]}"

# --- 7. Zip the App ---
echo "📦 Zipping application..."
APP_NAME="VirtualDisplayTest-darwin-$ARCH"
APP_PATH="$DIST_DIR/$APP_NAME/VirtualDisplayTest.app"
ZIP_PATH="$DIST_DIR/VirtualDisplayTest-macos-$ARCH.zip"

if [ -d "$APP_PATH" ]; then
    cd "$DIST_DIR/$APP_NAME"
    zip -r -y "$ZIP_PATH" "VirtualDisplayTest.app"
    echo "✅ Zipped to $ZIP_PATH"
else
    echo "❌ App not found at $APP_PATH"
    exit 1
fi

# --- 8. Upload to GitHub ---
if command -v gh &> /dev/null; then
    echo "☁️ GitHub CLI (gh) detected."
    
    # Check auth status
    if ! gh auth status &> /dev/null; then
        echo "⚠️ You are not logged in to gh. Run 'gh auth login' to enable upload."
        exit 0
    fi

    echo "   Authenticated."
    
    # Get Metadata
    PACKAGE_VERSION=$(node -p "require('$ROOT_DIR/package.json').version")
    DEFAULT_TAG="v$PACKAGE_VERSION"
    LATEST_RELEASE=$(gh release view --json tagName -q .tagName 2>/dev/null || echo "")

    TARGET_TAG=""

    # Interaction Loop
    if [ -n "$LATEST_RELEASE" ]; then
        echo "   Latest release found: $LATEST_RELEASE"
        echo "   [1] Upload to existing '$LATEST_RELEASE'"
        echo "   [2] Create and upload to new release '$DEFAULT_TAG'"
        echo "   [3] Create and upload to custom tag"
        echo "   [4] Skip upload"
        read -p "   Select option [1]: " OPTION
        OPTION=${OPTION:-1} # Default to 1
        
        case $OPTION in
            1) TARGET_TAG="$LATEST_RELEASE" ;;
            2) TARGET_TAG="$DEFAULT_TAG" ;;
            3) 
                read -p "   Enter tag name: " TARGET_TAG 
                ;;
            *) echo "   Skipped upload."; exit 0 ;;
        esac
    else
        echo "⚠️ No existing releases found."
        echo "   [1] Create and upload to new release '$DEFAULT_TAG'"
        echo "   [2] Create and upload to custom tag"
        echo "   [3] Skip upload"
        read -p "   Select option [1]: " OPTION
        OPTION=${OPTION:-1}
        
        case $OPTION in
            1) TARGET_TAG="$DEFAULT_TAG" ;;
            2) 
                read -p "   Enter tag name: " TARGET_TAG 
                ;;
            *) echo "   Skipped upload."; exit 0 ;;
        esac
    fi

    if [ -z "$TARGET_TAG" ]; then
        echo "❌ Invalid tag."
        exit 1
    fi

    # Check if release exists, create if not
    if ! gh release view "$TARGET_TAG" &> /dev/null; then
        echo "🆕 Creating release '$TARGET_TAG'..."
        if gh release create "$TARGET_TAG" --generate-notes; then
             echo "✅ Release '$TARGET_TAG' created."
        else
             echo "❌ Failed to create release."
             exit 1
        fi
    fi

    # Upload
    echo "🚀 Uploading to '$TARGET_TAG'..."
    gh release upload "$TARGET_TAG" "$ZIP_PATH" --clobber
    echo "✅ Upload complete!"

else
    echo "ℹ️ GitHub CLI (gh) not found. Skipping upload."
fi

echo "✨ Done!"
open "$DIST_DIR"
