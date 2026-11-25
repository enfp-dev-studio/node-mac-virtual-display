# node-mac-virtual-display

Public MIT N-API addon (Objective-C++) that creates macOS virtual displays via private `CGVirtualDisplay*` APIs. Main consumer: Tab Display. A regression can break a user's real desktop layout; keep API and semver stable.

## Layout
- `src/virtual_display.mm`: native `VDisplay`
- `src/index.ts`: TS wrapper and types; `dist/` is generated
- `test/module.spec.js`: Mocha + Chai

## Do not regress (change only on request)
- `PostProcessDisplay`: restore the original main display, prevent the primary from mirroring the virtual one, then apply the caller's mirror choice
- `EnsurePhysicalDisplayStaysMain` (via `RegisterScreenParamsObserver`): main slot (0,0) stays on a physical display whenever one is online (see `docs/IMPROVEMENTS.md`)
- `DestroyVirtualDisplay`: release descriptor → settings → display, then nil; every created display must be destroyed
- Parameters: refresh 30–120 Hz integer (clones report the real rate unrounded), PPI 72–300 (default 81), HiDPI = physical 2× logical at effective PPI 220
- JS and native both reject non-positive, non-integer and overflowing dimensions before touching an existing display
- `waitForDisplayMode()`: some Intel Macs first report a 1×1 placeholder mode
- Native parameter order and the `DisplayInfo` shape change together across layers or not at all

## Commands
```bash
npm run build             # host arch (node-gyp)
npm run build:prebuilds   # darwin-x64 + darwin-arm64, what ships
npm test                  # input validation, creates no display
npm run test:integration  # creates real displays, may disturb the desktop
npm run lint              # prettier + clang-format check (format: npm run format)
```

## Release
- Tarball ships both arch prebuilds, never `build/`; Tab Display needs both from one arm64 machine
- `v*` tag → `release-package.yml`: prebuilds, `lipo -archs` check, `npm publish --provenance`
- Tests cover the reported-info contract only, not capture readiness or Screen Recording permission
- API change: update `README.md`, types in `src/index.ts`, and this file
