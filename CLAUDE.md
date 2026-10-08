# CLAUDE.md - AI Assistant Guide for node-mac-virtual-display

## Project Overview

**node-mac-virtual-display** is a Native Node.js addon for macOS that enables creation and management of virtual displays. The library interfaces with macOS CoreGraphics and CoreDisplay APIs to provide programmatic control over virtual displays.

**Key Information:**
- **Language:** Objective-C++ (`.mm`), JavaScript, TypeScript definitions
- **Platform:** macOS 10.14+ only
- **Node.js:** v22+
- **License:** MIT
- **Version:** 1.0.17
- **Primary Use Case:** Used in [Tab Display](https://tab-display.enfpdev.com) for tablet-as-monitor functionality

## Codebase Structure

```
node-mac-virtual-display/
├── src/
│   ├── index.ts                 # TypeScript wrapper and API definitions
│   └── virtual_display.mm       # Main C++ native addon implementation
├── test/
│   └── module.spec.js           # Mocha test suite
├── .github/
│   ├── workflows/
│   │   ├── validate.yml         # PR/main build, test, lint and audit
│   │   └── release-package.yml  # CI/CD for package publishing
│   └── FUNDING.yml              # Funding configuration
├── dist/                        # Generated JavaScript and declarations
├── binding.gyp                  # Node-gyp build configuration
├── package.json                 # NPM package configuration
├── README.md                    # User-facing documentation
└── LICENSE                      # MIT License
```

## Architecture & Design

### Core Components

1. **Native C++ Layer** (`src/virtual_display.mm`)
   - Implements `VDisplay` class using N-API (Node Addon API)
   - Interfaces with private macOS frameworks:
     - `CGVirtualDisplay` - Main virtual display controller
     - `CGVirtualDisplayDescriptor` - Display hardware descriptor
     - `CGVirtualDisplaySettings` - Display mode settings
     - `CGVirtualDisplayMode` - Resolution/refresh rate configuration

2. **TypeScript Wrapper** (`src/index.ts`, compiled to `dist/index.js`)
   - Exports `VirtualDisplay` constructor
   - Provides clean API over native addon
   - Three main methods:
     - `createVirtualDisplay()` - Create custom display
     - `cloneVirtualDisplay()` - Clone main display
     - `destroyVirtualDisplay()` - Remove virtual display

3. **TypeScript Definitions** (`dist/index.d.ts`, generated from `src/index.ts`)
   - Type-safe interface definitions
   - Exports `DisplayInfo` type

### Key Design Patterns

- **Object-Oriented Wrapper:** JavaScript class wraps native addon instance
- **Resource Management:** Manual memory management in C++ with explicit cleanup
- **Configuration Objects:** Options passed as JavaScript objects with destructuring
- **Mirror Mode Handling:** Post-processing logic to prevent unintended main display changes

## Critical Implementation Details

### Display Creation Logic

When creating a virtual display, the code performs critical post-processing in `PostProcessDisplay` (`src/virtual_display.mm`):

1. **Main Display Restoration:** If virtual display becomes main display unintentionally, restore original
2. **Mirror Prevention:** Prevent primary display from mirroring virtual display
3. **Mirror Mode Configuration:** Apply user's mirror preference (extend vs mirror mode)

After creation, `RegisterScreenParamsObserver` subscribes to
`NSApplicationDidChangeScreenParametersNotification`. On every display-topology
change (e.g. a physical display hot-plug), `EnsurePhysicalDisplayStaysMain` runs
the physical-main safety net: whenever a physical display is online, the main
slot (0,0) must belong to a physical display — never the virtual one — otherwise
the menu bar, dock, and keyboard focus land on an invisible screen. This mirrors
the fix for SideScreen issue #39 (see docs/IMPROVEMENTS.md for source
attribution).

**IMPORTANT:** This post-processing logic and the main-display guard are
essential and should NOT be removed or modified without deep understanding of
macOS display behavior.

### Parameter Constraints

- **Refresh Rate:** Clamped to 30-120 Hz. `frameRate` is a positive integer.
  Returned rates are reported exactly as supplied for `create`; a clone reports
  the actual mode rate as-is (macOS can expose fractional values such as 59.94,
  which are not rounded).
- **PPI:** Clamped to 72-300 range
- **HiDPI Mode:** Physical (backing) resolution = 2x logical. The descriptor's
  `maxPixels*` are set to the physical size and the settings expose an anchor
  (physical) + logical mode pair, so macOS recognises the display as Retina
  (effective PPI forced to 220 when HiDPI).

### Memory Management

The native addon uses manual memory management:
- Objects allocated with `[[Class alloc] init]`
- Must be released with `[object release]` in `DestroyVirtualDisplay`
- Potential memory leak if display not properly destroyed

## Development Workflow

### Build System

**Technology:** node-gyp (native addon build tool)

**Commands:**
```bash
npm run build      # Rebuild native addon for the host arch (node-gyp rebuild)
npm run build:prebuilds # prebuildify: prebuilds/darwin-{x64,arm64}/ (what ships on npm)
npm run clean      # Clean build artifacts (node-gyp clean)
```

**Binary distribution:** the npm tarball carries `prebuilds/darwin-x64` and
`prebuilds/darwin-arm64` (see `files` in `package.json`); `build/` never
ships. `src/index.ts` loads through `node-gyp-build`, which prefers a local
`build/Release` (dev checkout) and otherwise selects the prebuild for
`process.arch`. The `install` script is `node-gyp-build` too, so a consumer
only compiles when no prebuild matches. Keep both architectures in the tarball:
consumers such as Tab Display package one `node_modules` into x64 and arm64
app bundles from a single arm64 build machine.

**Build Configuration** (`binding.gyp`):
- Target: `virtual_display.node`
- Compiler: Clang with C++17 standard
- macOS Deployment Target: 10.14
- Framework Dependencies: Cocoa, CoreGraphics, CoreVideo, IOKit
- Compiler Flags: `-std=c++17 -stdlib=libc++`
- N-API Exception Mode: `NAPI_DISABLE_CPP_EXCEPTIONS`

### Testing

**Framework:** Mocha + Chai

**Command:**
```bash
npm test                  # Safe input validation; creates no display
npm run test:integration  # Explicit real-display integration tests on macOS
```

**Test Characteristics:**
- Located in `test/module.spec.js`
- Two layers:
  1. **JS-layer validation tests** (safe on any platform) — assert bad inputs
     (non-integer/zero width/height, non-positive frameRate/PPI) throw before
     any display is created.
  2. **Integration tests** (macOS only) — create real virtual displays and
     verify `createVirtualDisplay`/`cloneVirtualDisplay`/`getDisplayInfo`
     output, including the HiDPI physical = 2x logical contract. Each test
     tears its display down in `afterEach` so a failure never leaks an
     orphaned display.
- Native argument validation rejects invalid dimensions without creating displays.
- Only `npm run test:integration` creates real displays on macOS. These tests
  do not capture screen contents and do not exercise Screen Recording permission.

### Code Quality & Formatting

**Linting:**
```bash
npm run lint       # Check formatting (dry-run)
npm run format     # Apply formatting
```

**Tools:**
- **JavaScript:** Prettier (`.js` files)
- **Objective-C++:** clang-format (`.mm` files)

**Git Hooks:**
- Husky configured for pre-commit hooks
- lint-staged runs formatters automatically:
  - `*.js` → prettier
  - `*.mm` → clang-format

### CI/CD Pipeline

**Workflow:** `.github/workflows/release-package.yml`

**Triggers:** On GitHub release creation

**Triggers:** On `v*` tag push

**Job** (single macOS arm64 runner):
- `npm ci`
- `npm run build:ts` — emit `dist/`
- `npm run build:prebuilds` — prebuildify both slices; the x64 one is cross-compiled
  with `node-gyp --arch x64`
- Verify each prebuild's architecture with `lipo -archs` (fails the job on a
  mismatch)
- `npm publish --provenance --access public`

**Registry:** npmjs.org

## Key Conventions

### Naming Conventions

- **Variables:** camelCase (`displayName`, `refreshRate`)
- **Classes:** PascalCase (`VirtualDisplay`, `VDisplay`)
- **Constants:** Regular case (no SCREAMING_SNAKE_CASE used)
- **Private Members:** Underscore prefix (`_display`, `_descriptor`, `_settings`)

### Code Style

**JavaScript:**
- Double quotes for strings
- Semicolons required
- 2-space indentation
- CommonJS modules (`require`/`module.exports`)

**Objective-C++:**
- Follows standard Objective-C conventions
- Uses ARC-style manual memory management
- NSLog for debugging output

### Error Handling

- **JavaScript Layer:** Returns results directly, no explicit error handling
- **Native Layer:** Throws JavaScript exceptions via N-API:
  - `Napi::TypeError` for wrong argument count
  - `Napi::Error` for runtime failures
- Returns `null`/`false` on errors

### API Design Philosophy

- **Destructured Parameters:** Methods accept single config object
- **Sensible Defaults:** PPI defaults to 81 (FHD monitor standard)
- **Return Values:** Always return `DisplayInfo` object with `{id, width, height}`

## Common Development Tasks

### Adding a New Feature

1. Modify native code in `src/virtual_display.mm`
2. Update TypeScript wrapper in `src/index.ts` if needed
3. Type declarations are emitted from `src/index.ts` to `dist/index.d.ts`
4. Add tests in `test/module.spec.js`
5. Run `npm run format` to format code
6. Run `npm run build` to compile
7. Run `npm test` to verify

### Modifying Display Configuration

When adding new display parameters:

1. **Update native method signature** in `VDisplay` class
2. **Update descriptor/settings initialization** in `InitializeDescriptor`/`InitializeSettings`
3. **Update TypeScript wrapper** parameter destructuring in `src/index.ts`
4. **Update TypeScript types** in `src/index.ts` (emit via `tsc`)
5. **Maintain parameter order** consistency across layers

### Debugging Native Code

- Use `NSLog()` for console output (visible in terminal)
- Logs include:
  - Display IDs during creation
  - Mirror mode state changes
  - Configuration errors
- Check macOS Console app for additional system logs

## Important Notes for AI Assistants

### Platform Constraints

1. **macOS Only:** This code CANNOT run on Windows/Linux - uses macOS-private APIs
2. **Requires macOS 10.14+:** Older versions lack `CGVirtualDisplay` APIs
3. **Architecture-Specific:** x86_64 and arm64 (Apple Silicon); both are prebuilt and shipped, node-gyp is only the fallback

### Critical Code Sections

**DO NOT MODIFY** without explicit user request:

1. **Post-processing logic** (lines 149-192, 239-282 in `virtual_display.mm`)
   - Prevents macOS display configuration bugs
   - Essential for maintaining primary display as main

2. **Memory management** in `DestroyVirtualDisplay`
   - Release order: descriptor → settings → display
   - Setting to nil prevents dangling pointers

3. **Mirror mode logic**
   - Complex interplay with macOS display management
   - Wrong configuration can cause display issues

### Security Considerations

- **Dimension validation:** JS and native reject non-positive, non-integer,
  and overflowing dimensions before replacing an existing display. HiDPI
  reserves room for 2x physical pixels in unsigned 32-bit fields.
- **Activation limits:** Numeric validation does not prove macOS can activate
  a requested mode. Actual mode reporting is unchanged in this update;
  existing descriptor fallbacks do not prove capture readiness.
- **Resource limits:** No check for maximum displays or system resources

**AI Assistant Action:** When adding features, validate user inputs for reasonableness.

### Breaking Changes to Avoid

1. **Changing parameter order** in native methods breaks JavaScript wrapper
2. **Modifying return object structure** breaks TypeScript definitions
3. **Changing N-API exception handling** can crash Node.js process
4. **Removing memory cleanup** causes memory leaks

### Building on Non-macOS

- Repository can be cloned anywhere
- `npm install` will fail on non-macOS (node-gyp compilation requires macOS frameworks)
- Package.json specifies `"os": ["darwin"]` to prevent installation on wrong platforms

### Testing Considerations

- `npm test` runs input validation without creating displays.
- `npm run test:integration` creates real displays on macOS and cleans them up.
- Integration tests may affect the active desktop layout.
- These tests verify the existing reported-info contract, including descriptor
  fallbacks; they do not independently prove live capture readiness.

### Documentation Updates

When modifying APIs, update:
1. `README.md` - User-facing documentation
2. `src/index.ts` - TypeScript API and generated definitions
3. `CLAUDE.md` - This file (AI assistant guide)
4. Inline code comments for complex logic

## Common Pitfalls

1. **Forgetting to destroy displays:** Memory leaks and orphaned displays
2. **Modifying mirror logic:** Can break display configuration on user's Mac
3. **Not testing on real macOS:** Code must be tested on actual macOS hardware
4. **Ignoring clang-format:** Pre-commit hooks will fail
5. **Breaking API compatibility:** This is a library - semver matters

## Development Environment Setup

```bash
# Clone repository
git clone https://github.com/ENFP-Dev-Studio/node-mac-virtual-display.git
cd node-mac-virtual-display

# Install dependencies (macOS only)
yarn install

# Build native addon
npm run build

# Run input validation (creates no displays)
npm test

# Format code
npm run format

# Check formatting
npm run lint
```

## Version History Context

- **v1.0.17:** Current version
- Recent changes focused on:
  - Virtual display as main display handling
  - HiDPI scaling adjustments
  - Bug fixes for display configuration

## Related Resources

- **Tab Display:** https://tab-display.enfpdev.com
- **N-API Documentation:** https://nodejs.org/api/n-api.html
- **node-gyp Guide:** https://github.com/nodejs/node-gyp
- **macOS CoreGraphics:** Apple Developer Documentation (private APIs used)

## Support & Contribution

- **Issues:** GitHub Issues
- **Funding:** Buy Me a Coffee, Patreon (see FUNDING.yml)
- **Author:** ENFP-Dev-Studio (Jake Roh)

---

**Last Updated:** 2026-10-08
**Repository Version:** 1.0.17
