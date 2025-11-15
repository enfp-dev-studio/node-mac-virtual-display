# CLAUDE.md - AI Assistant Guide for node-mac-virtual-display

## Project Overview

**node-mac-virtual-display** is a Native Node.js addon for macOS that enables creation and management of virtual displays. The library interfaces with macOS CoreGraphics and CoreDisplay APIs to provide programmatic control over virtual displays.

**Key Information:**
- **Language:** Objective-C++ (`.mm`), JavaScript, TypeScript definitions
- **Platform:** macOS 10.14+ only
- **Node.js:** v12+
- **License:** MIT
- **Version:** 1.0.9
- **Primary Use Case:** Used in [Tab Display](https://tab-display.enfpdev.com) for tablet-as-monitor functionality

## Codebase Structure

```
node-mac-virtual-display/
├── src/
│   └── virtual_display.mm       # Main C++ native addon implementation
├── test/
│   └── module.spec.js           # Mocha test suite
├── .github/
│   ├── workflows/
│   │   └── release-package.yml  # CI/CD for package publishing
│   └── FUNDING.yml              # Funding configuration
├── index.js                     # JavaScript wrapper/entry point
├── index.d.ts                   # TypeScript type definitions
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

2. **JavaScript Wrapper** (`index.js`)
   - Exports `VirtualDisplay` constructor
   - Provides clean API over native addon
   - Three main methods:
     - `createVirtualDisplay()` - Create custom display
     - `cloneVirtualDisplay()` - Clone main display
     - `destroyVirtualDisplay()` - Remove virtual display

3. **TypeScript Definitions** (`index.d.ts`)
   - Type-safe interface definitions
   - Exports `DisplayInfo` type

### Key Design Patterns

- **Object-Oriented Wrapper:** JavaScript class wraps native addon instance
- **Resource Management:** Manual memory management in C++ with explicit cleanup
- **Configuration Objects:** Options passed as JavaScript objects with destructuring
- **Mirror Mode Handling:** Post-processing logic to prevent unintended main display changes

## Critical Implementation Details

### Display Creation Logic

When creating a virtual display, the code performs critical post-processing (lines 149-192 in `virtual_display.mm`):

1. **Main Display Restoration:** If virtual display becomes main display unintentionally, restore original
2. **Mirror Prevention:** Prevent primary display from mirroring virtual display
3. **Mirror Mode Configuration:** Apply user's mirror preference (extend vs mirror mode)

**IMPORTANT:** This post-processing logic is essential and should NOT be removed or modified without deep understanding of macOS display behavior.

### Parameter Constraints

- **Refresh Rate:** Clamped to 30-60 Hz range
- **PPI:** Clamped to 72-300 range
- **HiDPI Mode:** When enabled, creates both full-res and half-res modes

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
npm run build      # Rebuild native addon (node-gyp rebuild)
npm run clean      # Clean build artifacts (node-gyp clean)
```

**Build Configuration** (`binding.gyp`):
- Target: `virtual_display.node`
- Compiler: Clang with C++14 standard
- macOS Deployment Target: 10.14
- Framework Dependencies: StoreKit
- Compiler Flags: `-std=c++14 -stdlib=libc++`
- N-API Exception Mode: `NAPI_DISABLE_CPP_EXCEPTIONS`

### Testing

**Framework:** Mocha + Chai

**Command:**
```bash
npm test           # Run test suite
```

**Test Characteristics:**
- Located in `test/module.spec.js`
- Tests create display and wait 10 minutes before cleanup (600000ms timeout)
- Only basic smoke test - verifies module doesn't throw on initialization
- Clone test commented out by default

**IMPORTANT:** Tests create real virtual displays - must run on macOS with proper permissions.

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

**Jobs:**
1. **Build** (macOS runner)
   - Checkout code
   - Setup Node.js 16
   - Run `npm build`
   - Run `npm test`

2. **Publish** (macOS runner, requires build success)
   - Checkout code
   - Setup Node.js 16 with GitHub Package Registry
   - Run `npm build`
   - Run `npm publish` to GitHub Packages

**Registry:** GitHub Packages (`https://npm.pkg.github.com`)

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
2. Update JavaScript wrapper in `index.js` if needed
3. Update TypeScript definitions in `index.d.ts`
4. Add tests in `test/module.spec.js`
5. Run `npm run format` to format code
6. Run `npm run build` to compile
7. Run `npm test` to verify

### Modifying Display Configuration

When adding new display parameters:

1. **Update native method signature** in `VDisplay` class
2. **Update descriptor/settings initialization** in `InitializeDescriptor`/`InitializeSettings`
3. **Update JavaScript wrapper** parameter destructuring
4. **Update TypeScript types** in `index.d.ts`
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
3. **Architecture-Specific:** x86_64 and arm64 (Apple Silicon) support via node-gyp

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

- **No input validation on dimensions:** Width/height not validated beyond type checking
- **Extreme values:** Could cause system issues (very large displays, extreme PPI)
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

- Tests create **real virtual displays**
- Requires **Screen Recording permission** on macOS 10.15+
- May affect active displays during development
- 10-minute timeout allows manual inspection of created display

### Documentation Updates

When modifying APIs, update:
1. `README.md` - User-facing documentation
2. `index.d.ts` - TypeScript definitions
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

# Run tests (creates real display - be prepared!)
npm test

# Format code
npm run format

# Check formatting
npm run lint
```

## Version History Context

- **v1.0.9:** Current version
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

**Last Updated:** 2025-11-15 (Auto-generated by Claude)
**Repository Version:** 1.0.9
