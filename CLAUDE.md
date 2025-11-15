# CLAUDE.md - AI Assistant Guide for node-mac-virtual-display

This document provides comprehensive guidance for AI assistants working with the `node-mac-virtual-display` codebase.

## Project Overview

**node-mac-virtual-display** is a native Node.js addon that enables programmatic creation and management of virtual displays on macOS. It uses private CoreGraphics and CoreDisplay APIs to provide virtual display functionality, primarily used in [Tab Display](https://tab-display.enfpdev.com) to turn iPads and Android tablets into portable monitors.

### Key Facts
- **Language**: Objective-C++ (.mm), JavaScript (Node.js)
- **Platform**: macOS 10.14+ only (darwin)
- **Version**: 1.0.9
- **License**: MIT
- **Repository**: https://github.com/ENFP-Dev-Studio/node-mac-virtual-display

## Repository Structure

```
node-mac-virtual-display/
├── src/
│   └── virtual_display.mm      # Native C++ implementation using CoreGraphics APIs
├── test/
│   └── module.spec.js          # Mocha/Chai test suite
├── .github/
│   └── workflows/
│       └── release-package.yml # CI/CD for releases
├── index.js                    # JavaScript wrapper/entry point
├── index.d.ts                  # TypeScript type definitions
├── binding.gyp                 # node-gyp build configuration
├── package.json                # NPM package configuration
└── README.md                   # User-facing documentation
```

### Critical Files

1. **src/virtual_display.mm** (300 lines)
   - Core native implementation
   - Defines private CoreGraphics interfaces (@interface declarations)
   - Implements VDisplay class with N-API bindings
   - Handles display creation, cloning, and destruction
   - Contains display configuration logic to prevent unintended display behaviors

2. **index.js** (47 lines)
   - JavaScript wrapper around native addon
   - Exports VirtualDisplay constructor
   - Provides high-level API methods
   - Sets default PPI value (81 for FHD monitors)

3. **index.d.ts** (33 lines)
   - TypeScript definitions for public API
   - Defines DisplayInfo return type
   - Documents function signatures

4. **binding.gyp** (30 lines)
   - node-gyp configuration
   - macOS-specific build settings
   - Links StoreKit framework
   - Sets C++14 standard and macOS deployment target 10.14

## Architecture & Implementation Details

### Native API Architecture

The module uses **N-API (Node-API)** for native bindings, ensuring ABI stability across Node.js versions.

**Class Structure:**
```cpp
VDisplay : public Napi::ObjectWrap<VDisplay>
├── CreateVirtualDisplay()     // Custom display with specified parameters
├── CloneVirtualDisplay()      // Clone main display configuration
├── DestroyVirtualDisplay()    // Cleanup and remove display
└── Helper Methods:
    ├── InitializeDescriptor() // Setup display metadata
    ├── InitializeSettings()   // Configure display modes
    └── CreateDisplayObject()  // Return JS object with display info
```

### Private CoreGraphics APIs

The code uses **undocumented Apple private APIs**:

```objective-c
@interface CGVirtualDisplayDescriptor
@interface CGVirtualDisplaySettings
@interface CGVirtualDisplayMode
@interface CGVirtualDisplay
```

**Important**: These APIs are private and not officially supported by Apple. They may change or break in future macOS versions without notice.

### Display Configuration Post-Processing

Both `CreateVirtualDisplay` and `CloneVirtualDisplay` implement critical post-processing logic (lines 149-192 and 239-282):

1. **Prevent Virtual Display as Main Display**
   - Checks if newly created virtual display became the main display
   - Restores original main display using `CGConfigureDisplayOrigin`
   - Logged as "Unintended case 1"

2. **Prevent Primary Display Mirroring Virtual Display**
   - Checks if primary display is mirroring the virtual display
   - Disables incorrect mirror configuration
   - Logged as "Unintended case 2"

3. **Configure Requested Mirror Mode**
   - Sets mirror mode based on `useMirror` parameter
   - Uses `CGConfigureDisplayMirrorOfDisplay` API
   - Applies configuration with `kCGConfigureForAppOnly` flag

### HiDPI Support

When `hiDPI` is enabled (lines 85-96):
- Creates two display modes: full resolution and half resolution
- Half resolution mode enables HiDPI scaling (2x pixel density)
- Example: 3840x2400 display also supports 1920x1200 @ 2x scaling

### Parameter Validation

The code implements clamping for certain parameters (lines 57-59, 118, 121):
- **Refresh Rate**: Clamped to 30-60 Hz
- **PPI**: Clamped to 72-300 DPI

## Public API

### Constructor
```javascript
const VirtualDisplay = require('node-mac-virtual-display')
const vdisplay = new VirtualDisplay()
```

### Methods

#### createVirtualDisplay(options)
Creates a virtual display with custom parameters.

**Parameters:**
- `width` (number): Display width in pixels
- `height` (number): Display height in pixels
- `frameRate` (number): Refresh rate (30-60 Hz, clamped)
- `hiDPI` (boolean): Enable HiDPI/Retina support
- `displayName` (string): Display name shown in System Preferences
- `ppi` (number, optional): Pixels per inch (72-300, default: 81)
- `mirror` (boolean): Enable mirror mode

**Returns:** `DisplayInfo` object
```javascript
{
  id: number,      // CGDirectDisplayID
  width: number,   // Display width
  height: number   // Display height
}
```

#### cloneVirtualDisplay(options)
Creates a virtual display matching the main display's configuration.

**Parameters:**
- `displayName` (string): Display name
- `mirror` (boolean): Enable mirror mode

**Returns:** `DisplayInfo` object

**Implementation Notes:**
- Automatically detects main display resolution, refresh rate, and DPI
- Calculates DPI from physical screen size
- Enables HiDPI if detected DPI > 200
- Inherits product/vendor IDs from main display (with offset)

#### destroyVirtualDisplay()
Destroys the current virtual display and releases resources.

**Returns:** `boolean` (true if display was destroyed, false if none existed)

**Memory Management:** Properly releases Objective-C objects using manual reference counting.

## Development Workflow

### Prerequisites
- macOS 10.14 or later
- Node.js 12 or later
- Xcode Command Line Tools (for clang)
- node-gyp globally installed (recommended)

### Setup
```bash
# Install dependencies
yarn install

# Build native addon
yarn build
# or
node-gyp rebuild

# Run tests
yarn test
```

### Code Formatting

The project uses **automated code formatting** enforced via git hooks:

- **JavaScript**: Prettier (`.js` files)
- **Objective-C++**: clang-format (`.mm` files)

**Commands:**
```bash
# Check formatting (dry-run)
yarn lint

# Apply formatting
yarn format
```

### Git Hooks (Husky + lint-staged)

**Pre-commit hook** automatically formats staged files:
- Runs `prettier --write` on `*.js` files
- Runs `clang-format -i` on `*.mm` files

**Setup:** `yarn prepare` (runs `husky install`)

### Testing

**Framework**: Mocha + Chai

**Test file**: `test/module.spec.js`

**Current test**: Creates a 3840x2400 virtual display, waits 10 minutes, then destroys it.

**Note**: Test has a 600-second (10-minute) timeout for manual verification.

### Building

The native addon is built using **node-gyp**:

```bash
# Clean build artifacts
yarn clean

# Build addon
yarn build
```

**Build output**: `build/Release/virtual_display.node` (gitignored)

**Build configuration** (binding.gyp):
- Target: virtual_display
- Sources: src/virtual_display.mm (macOS only)
- Framework: StoreKit
- C++ Standard: C++14 with libc++
- Deployment target: macOS 10.14
- N-API: CPP exceptions disabled

## CI/CD Pipeline

**GitHub Actions workflow**: `.github/workflows/release-package.yml`

**Trigger**: On GitHub release creation

**Jobs:**
1. **build** (macos-latest)
   - Checkout code
   - Setup Node.js 16
   - Run `npm build`
   - Run `npm test`

2. **publish-gpr** (macos-latest, after build)
   - Checkout code
   - Setup Node.js 16 with GitHub Packages registry
   - Run `npm build`
   - Publish to GitHub Packages (@enfp-dev-studio scope)

**Important**: The workflow uses `npm build` and `npm test`, but the project uses yarn. This may need correction.

## Key Conventions for AI Assistants

### Code Style

1. **Objective-C++ (.mm files)**
   - Use clang-format (runs automatically via git hooks)
   - Follow Apple naming conventions for Objective-C classes
   - Use NSLog for debugging output
   - Manual reference counting: `alloc/init`, `release`, set to `nil`

2. **JavaScript (.js files)**
   - Use Prettier formatting
   - Strict mode: `"use strict";`
   - Use function constructors (ES5 style, not ES6 classes)
   - Use CommonJS modules (`require`/`module.exports`)

3. **TypeScript Definitions (.d.ts)**
   - Export types and functions at top level
   - Use object destructuring notation for parameters
   - Keep in sync with actual implementation

### Error Handling

- **Native code**: Throw N-API JavaScript exceptions
  ```cpp
  Napi::TypeError::New(env, "Error message").ThrowAsJavaScriptException();
  return env.Null();
  ```
- **JavaScript wrapper**: Let native exceptions propagate
- **Always check**: NULL/nil pointers before use

### Memory Management

**Critical**: The native code uses manual reference counting (not ARC).

**Pattern:**
```objective-c
_descriptor = [[CGVirtualDisplayDescriptor alloc] init];  // +1 retain
// ... use descriptor ...
[_descriptor release];  // -1 retain
_descriptor = nil;      // Clear pointer
```

**When modifying**: Ensure all `alloc/init` calls have corresponding `release` calls in `DestroyVirtualDisplay`.

### Testing Approach

- **Manual testing recommended**: Virtual displays affect system state
- **Long-running tests**: Current test waits 10 minutes for manual verification
- **Test on real macOS**: Cannot be tested in CI on Linux/Windows
- **Check System Preferences**: Verify display appears in macOS settings

### Display Configuration Safety

**Always preserve** the post-processing logic in both create/clone methods:
1. Check and restore main display position
2. Check and fix mirror configuration
3. Apply requested mirror mode

**Removing this logic** will cause unpredictable display behavior and user confusion.

### Platform Constraints

- **macOS only**: Code will not compile or run on Linux/Windows
- **package.json** enforces: `"os": ["darwin"]`
- **binding.gyp** uses conditions: `'OS=="mac"'`
- **Always check**: OS-specific code paths

### Breaking Changes to Avoid

1. **Do not modify** private CoreGraphics interface definitions without testing on multiple macOS versions
2. **Do not remove** display configuration post-processing (unintended cases 1 & 2)
3. **Do not change** N-API signatures without updating TypeScript definitions
4. **Do not break** backward compatibility in public API (createVirtualDisplay, cloneVirtualDisplay, destroyVirtualDisplay)

### Version Management

- Update version in `package.json` before release
- Follow semantic versioning (currently 1.0.9)
- Create GitHub release to trigger publish workflow
- Recent versions: 1.0.9 (current), 1.0.8, earlier versions

### Documentation Updates

When modifying the API or adding features:
1. Update `README.md` with usage examples
2. Update `index.d.ts` with TypeScript definitions
3. Update this `CLAUDE.md` with implementation details
4. Add/update tests in `test/module.spec.js`

## Common Tasks

### Adding a New Display Parameter

1. Add parameter to `createVirtualDisplay` in `index.js`
2. Pass parameter to `_addonInstance.createVirtualDisplay()`
3. Update `CreateVirtualDisplay` in `virtual_display.mm` to accept new parameter
4. Use parameter in `InitializeDescriptor` or `InitializeSettings`
5. Update TypeScript definitions in `index.d.ts`
6. Update README.md usage examples
7. Add test coverage

### Debugging Native Code

**NSLog output** appears in Console.app:
1. Open Console.app on macOS
2. Filter by process name (your Node.js process)
3. Look for logs like "Virtual display created with ID: XXX"

**Common log messages:**
- "Previous Main display ID: X"
- "Current Main Display after virtual display creation: X"
- "Unintended case 1: Virtual display set as main display"
- "Unintended case 2: Primary display is mirroring virtual display"
- "Virtual Display is in mirror set: X"
- "Enable/Disable Virtual Display mirror mode"
- "Failed to enable/disable mirror mode: X"
- "Virtual display created with ID: X"

### Troubleshooting Build Issues

**Common problems:**
1. **Missing Xcode tools**: Install with `xcode-select --install`
2. **Wrong Node.js version**: Use Node.js 12+
3. **node-gyp not found**: Install globally with `npm install -g node-gyp`
4. **Framework not found**: Ensure Xcode Command Line Tools are properly installed

**Clean rebuild:**
```bash
yarn clean
rm -rf build/
yarn build
```

## Known Limitations

1. **Single virtual display**: Only one virtual display can exist at a time (multiple displays support is planned)
2. **macOS only**: Will never support Windows or Linux (requires macOS-specific APIs)
3. **Private APIs**: May break in future macOS versions
4. **No official Apple support**: Uses undocumented APIs
5. **Requires elevated permissions**: May require screen recording permissions in System Preferences

## Future Enhancements

From README.md features checklist:
- [ ] Support for multiple virtual displays (currently limited to one)

## Related Resources

- **Tab Display**: https://tab-display.enfpdev.com (main use case)
- **Node-API docs**: https://nodejs.org/api/n-api.html
- **node-gyp docs**: https://github.com/nodejs/node-gyp
- **CoreGraphics**: https://developer.apple.com/documentation/coregraphics (official APIs only)

## Questions to Consider When Making Changes

1. Does this change affect display configuration logic? (Test for unintended cases 1 & 2)
2. Does this change affect memory management? (Check for leaks)
3. Does this change break the public API? (Maintain backward compatibility)
4. Does this change work across different macOS versions? (Test on multiple versions)
5. Does this change affect TypeScript definitions? (Update index.d.ts)
6. Does this change require documentation updates? (Update README.md)
7. Can this change be tested automatically? (Add/update tests)
8. Does this change affect the build process? (Test clean build)

## Working with AI Assistants - Best Practices

When working with this codebase:

1. **Always read the native code** before suggesting changes to display logic
2. **Preserve memory management patterns** - use the same alloc/release patterns
3. **Test on actual macOS** - virtual displays cannot be fully simulated
4. **Maintain backward compatibility** - this is a published npm package
5. **Update all related files** - JS, TS definitions, docs, tests
6. **Follow existing code style** - let formatters handle styling
7. **Understand the post-processing logic** - critical for correct display behavior
8. **Document changes thoroughly** - explain why, not just what
9. **Consider macOS version compatibility** - private APIs may change
10. **Be cautious with private APIs** - we're relying on undocumented behavior

---

**Last Updated**: 2025-11-15
**Document Version**: 1.0
**For**: node-mac-virtual-display v1.0.9
