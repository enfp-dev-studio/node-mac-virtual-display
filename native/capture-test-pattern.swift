// Original validation fixture. Inspired by SideScreen's animated pattern tests,
// without copying its renderer, digit bitmaps, or production capture code.
import AppKit
import CoreGraphics
import Foundation
import Metal
import MetalKit
import QuartzCore

func emit(_ value: [String: Any]) {
    guard let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
    FileHandle.standardOutput.write(bytes + Data([10]))
}

final class PatternView: NSView {
    let pixelsWide: Int
    let pixelsHigh: Int
    let epoch = ProcessInfo.processInfo.systemUptime
    var draws = 0
    var referenceTime: Double?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    init(frame: NSRect, width: Int, height: Int) {
        pixelsWide = width
        pixelsHigh = height
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        draws += 1
        let w = bounds.width
        let h = bounds.height
        func rectangle(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ color: NSColor) {
            color.setFill()
            NSRect(x: x * w, y: y * h, width: width * w, height: height * h).fill()
        }
        rectangle(0, 0, 1, 1, .black)
        rectangle(0.012, 0.012, 0.976, 0.976, .white)
        rectangle(0.024, 0.024, 0.952, 0.952, .black)
        rectangle(0.032, 0.032, 0.936, 0.936, .white)
        let colors: [NSColor] = [.white, .yellow, .cyan, .green, .magenta, .red, .blue, .black]
        for (index, color) in colors.enumerated() {
            rectangle(0.04 + Double(index) * 0.115, 0.045, 0.115, 0.09, color)
        }
        let text = "HEVC 0123456789 | HiDPI AaBbMmWw"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: h * 0.043, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        (text as NSString).draw(at: NSPoint(x: 0.05 * w, y: 0.19 * h), withAttributes: attributes)
        for index in 0..<8 {
            rectangle(0.05, 0.265 + Double(index) / Double(pixelsHigh) * 2, 0.9, 1 / Double(pixelsHigh), .black)
        }
        rectangle(0.04, 0.35, 0.92, 0.23, NSColor(white: 0.1, alpha: 1))
        let elapsed = referenceTime ?? (ProcessInfo.processInfo.systemUptime - epoch)
        let phase = (elapsed * 0.31).truncatingRemainder(dividingBy: 1)
        rectangle(0.04 + phase * 0.82, 0.35, 0.1, 0.23, .white)
        (String(format: "%.3f s", elapsed) as NSString).draw(
            at: NSPoint(x: 0.42 * w, y: 0.44 * h), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: h * 0.05, weight: .bold),
                .foregroundColor: NSColor.red
            ])
        let cell = 8.0 / Double(pixelsWide)
        let cellY = 8.0 / Double(pixelsHigh)
        let columns = Int(0.42 / cell)
        let rows = Int(0.25 / cellY)
        for row in 0..<rows {
            for column in 0..<columns where (row + column).isMultiple(of: 2) {
                rectangle(0.05 + Double(column) * cell, 0.65 + Double(row) * cellY, cell, cellY, .black)
            }
        }
        ("Text: 1px / 8px checker" as NSString).draw(
            at: NSPoint(x: 0.52 * w, y: 0.69 * h), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: h * 0.027, weight: .regular),
                .foregroundColor: NSColor.black
            ])
        ("Sharp edges stay aligned" as NSString).draw(
            at: NSPoint(x: 0.52 * w, y: 0.76 * h), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: h * 0.027, weight: .bold),
                .foregroundColor: NSColor.black
            ])
    }

    func saveReference(to path: String) throws {
        guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide,
                                          pixelsHigh: pixelsHigh, bitsPerSample: 8,
                                          samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                          colorSpaceName: .deviceRGB, bytesPerRow: pixelsWide * 4,
                                          bitsPerPixel: 32), let context = NSGraphicsContext(bitmapImageRep: image) else {
            throw NSError(domain: "Pattern", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate reference bitmap"])
        }
        image.size = bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // Match the flipped view's coordinate system in the independent bitmap.
        let graphics = context.cgContext
        graphics.translateBy(x: 0, y: CGFloat(pixelsHigh))
        graphics.scaleBy(x: CGFloat(pixelsWide) / bounds.width, y: -CGFloat(pixelsHigh) / bounds.height)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: graphics, flipped: true)
        referenceTime = 0
        draw(bounds)
        referenceTime = nil
        NSGraphicsContext.restoreGraphicsState()
        guard let png = image.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Pattern", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to encode reference bitmap"])
        }
        try png.write(to: URL(fileURLWithPath: path))
    }
}

protocol QualityMetalSource: AnyObject {
    var marker: [String: Any] { get }
    var gpuName: String { get }
    func start()
    func stop()
    func snapshot() -> [String: Any]
}

struct QualityFrameParameters {
    var frameID: UInt32
    var width: UInt32
    var height: UInt32
    var cell: UInt32
    var left: UInt32
    var top: UInt32
    var right: UInt32
    var bottom: UInt32
    var fps: UInt32
}

@available(macOS 14.0, *)
final class MetalQualityRenderer: NSObject, QualityMetalSource, CAMetalDisplayLinkDelegate {
    let layer: CAMetalLayer
    let base: MTLTexture
    let queue: MTLCommandQueue
    let pipeline: MTLComputePipelineState
    let width: Int
    let height: Int
    let fps: Int
    let cell: Int
    let left: Int
    let top: Int
    let right: Int
    let bottom: Int
    let gpuName: String
    let epoch = CACurrentMediaTime()
    let lock = NSLock()
    var link: CAMetalDisplayLink!
    var callbacks: UInt64 = 0
    var submitted: UInt64 = 0
    var completed: UInt64 = 0
    var commandErrors: UInt64 = 0
    var deadlineMisses: UInt64 = 0
    var zeroPresentedTimeCallbacks: UInt64 = 0
    var positivePresentedTimeCallbacks: UInt64 = 0
    var submissionTimes: [Double] = []
    var completionTimes: [Double] = []
    var callbackTimes: [Double] = []
    var gpuDurations: [Double] = []
    var submittedIDs: Set<UInt16> = []
    var lastError = ""

    var marker: [String: Any] {
        ["bits": 16, "endianness": "little", "origin": "top-left", "cell": cell,
         "x": left + cell + cell / 2, "y": top + cell / 2,
         "whiteAnchorX": left + cell / 2, "blackAnchorX": left + 17 * cell + cell / 2,
         "motionRegion": ["left": left, "top": top, "right": right, "bottom": bottom]]
    }

    init(layer: CAMetalLayer, device: MTLDevice, reference: URL, width: Int, height: Int, fps: Int) throws {
        self.layer = layer; self.width = width; self.height = height; self.fps = fps
        gpuName = device.name
        let motionLeft = Int(ceil(Double(width) * 0.04)), motionRight = Int(floor(Double(width) * 0.96))
        let motionTop = Int(ceil(Double(height) * 0.35)), motionBottom = Int(floor(Double(height) * 0.58))
        let markerCell = min(32, (motionRight - motionLeft) / 18, motionBottom - motionTop)
        left = motionLeft; right = motionRight; top = motionTop; bottom = motionBottom; cell = markerCell
        guard markerCell >= 2, let queue = device.makeCommandQueue() else {
            throw NSError(domain: "QualityMetal", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Motion region or Metal command queue is unavailable"])
        }
        self.queue = queue
        // Read the original physical-pixel PNG without filtering, mipmaps,
        // rescaling, or an implicit sRGB decode. Only the motion region changes.
        let original = try MTKTextureLoader(device: device).newTexture(URL: reference, options: [
            .origin: MTKTextureLoader.Origin.topLeft.rawValue,
            .SRGB: false, .generateMipmaps: false,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
        ])
        guard original.width == width, original.height == height else {
            throw NSError(domain: "QualityMetal", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Reference texture differs from the exact capture dimensions"])
        }
        base = original
        let shader = """
        #include <metal_stdlib>
        using namespace metal;
        struct Parameters { uint frameID; uint width; uint height; uint cell;
                            uint left; uint top; uint right; uint bottom; uint fps; };
        kernel void qualityPattern(texture2d<float, access::read> base [[texture(0)]],
                                   texture2d<float, access::write> target [[texture(1)]],
                                   constant Parameters &p [[buffer(0)]], uint2 xy [[thread_position_in_grid]]) {
            if (xy.x >= p.width || xy.y >= p.height) return;
            float4 color = base.read(xy);
            if (xy.x >= p.left && xy.x < p.right && xy.y >= p.top && xy.y < p.bottom) {
                color = float4(0.1f, 0.1f, 0.1f, 1.0f);
                uint barWidth = max(1u, p.width / 10u);
                float phase = fract(float(p.frameID) * 0.31f / float(p.fps));
                uint barLeft = p.left + uint(phase * float(p.right - p.left - barWidth));
                if (xy.x >= barLeft && xy.x < barLeft + barWidth) color = float4(1.0f);
                // All 18 marker cells stay strictly inside the original motion
                // region: white guard, 16 little-endian bits, black guard.
                if (xy.y < p.top + p.cell && xy.x < p.left + 18u * p.cell) {
                    uint index = (xy.x - p.left) / p.cell;
                    bool white = index == 0u || (index <= 16u && (p.frameID & (1u << (index - 1u))) != 0u);
                    color = white ? float4(1.0f) : float4(0.0f, 0.0f, 0.0f, 1.0f);
                }
            }
            target.write(color, xy);
        }
        """
        let library = try device.makeLibrary(source: shader, options: nil)
        guard let function = library.makeFunction(name: "qualityPattern") else {
            throw NSError(domain: "QualityMetal", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "GPU quality pattern function is unavailable"])
        }
        pipeline = try device.makeComputePipelineState(function: function)
        super.init()
        link = CAMetalDisplayLink(metalLayer: layer)
        link.delegate = self
        let rate = Float(fps)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
    }

    func start() { link.add(to: .main, forMode: .common) }
    func stop() { link.invalidate() }

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        autoreleasepool {
            lock.lock(); callbacks += 1; let frameID = UInt16(truncatingIfNeeded: callbacks)
            callbackTimes.append(CACurrentMediaTime()); lock.unlock()
            guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
                lock.lock(); commandErrors += 1; lastError = "GPU command allocation failed"; lock.unlock()
                return
            }
            var parameters = QualityFrameParameters(frameID: UInt32(frameID), width: UInt32(width), height: UInt32(height),
                                                    cell: UInt32(cell), left: UInt32(left), top: UInt32(top),
                                                    right: UInt32(right), bottom: UInt32(bottom), fps: UInt32(fps))
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(base, index: 0); encoder.setTexture(update.drawable.texture, index: 1)
            encoder.setBytes(&parameters, length: MemoryLayout<QualityFrameParameters>.stride, index: 0)
            let threadWidth = pipeline.threadExecutionWidth
            let threadHeight = max(1, min(8, pipeline.maxTotalThreadsPerThreadgroup / threadWidth))
            encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1))
            encoder.endEncoding()
            command.addCompletedHandler { [weak self] completedCommand in
                guard let self else { return }
                self.lock.lock(); defer { self.lock.unlock() }
                self.completed += 1; self.completionTimes.append(CACurrentMediaTime())
                if completedCommand.status == .error {
                    self.commandErrors += 1
                    self.lastError = completedCommand.error?.localizedDescription ?? "GPU command failed"
                }
                let start = completedCommand.gpuStartTime, end = completedCommand.gpuEndTime
                if start > 0 && end >= start { self.gpuDurations.append((end - start) * 1000) }
            }
            update.drawable.addPresentedHandler { [weak self] drawable in
                guard let self else { return }
                self.lock.lock(); defer { self.lock.unlock() }
                if drawable.presentedTime > 0 { self.positivePresentedTimeCallbacks += 1 }
                else { self.zeroPresentedTimeCallbacks += 1 }
            }
            lock.lock(); submitted += 1; submissionTimes.append(CACurrentMediaTime())
            submittedIDs.insert(frameID); lock.unlock()
            command.commit()
            if CACurrentMediaTime() > update.targetTimestamp { lock.lock(); deadlineMisses += 1; lock.unlock() }
            update.drawable.present()
        }
    }

    func snapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        func frameRate(_ times: [Double]) -> Double {
            guard times.count > 1, let first = times.first, let last = times.last, last > first else { return 0 }
            return Double(times.count - 1) / (last - first)
        }
        return ["producer": "CAMetalDisplayLink", "callbacks": callbacks,
                "submitted": submitted, "completed": completed,
                "callbackFPS": frameRate(callbackTimes), "submittedFPS": frameRate(submissionTimes),
                "completedFPS": frameRate(completionTimes), "frameId": callbacks & 65535,
                "uniqueSubmittedFrameIDs": submittedIDs.count, "commandErrors": commandErrors,
                "deadlineMisses": deadlineMisses, "lastError": lastError,
                "gpuMeanMs": gpuDurations.isEmpty ? 0 : gpuDurations.reduce(0, +) / Double(gpuDurations.count),
                "gpuMaxMs": gpuDurations.max() ?? 0,
                "zeroPresentedTimeCallbacks": zeroPresentedTimeCallbacks,
                "presentationTimestampSupported": positivePresentedTimeCallbacks > 0, "marker": marker]
    }
}

let arguments = CommandLine.arguments
guard (6...7).contains(arguments.count), let requestedID = UInt32(arguments[1]),
      let expectedWidth = Int(arguments[2]), let expectedHeight = Int(arguments[3]),
      let fps = Int(arguments[4]), (1...240).contains(fps) else {
    fputs("Usage: capture-test-pattern display-id physical-width physical-height fps reference.png [appkit-buffered|layer-flush|metal-display-link]\n", stderr)
    exit(2)
}
let renderingMode = arguments.count == 7 ? arguments[6] : "appkit-buffered"
guard ["appkit-buffered", "layer-flush", "metal-display-link"].contains(renderingMode) else {
    fputs("Rendering mode must be appkit-buffered, layer-flush, or metal-display-link\n", stderr)
    exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()
let deadline = ProcessInfo.processInfo.systemUptime + 10
var selectedScreen: NSScreen?
repeat {
    selectedScreen = NSScreen.screens.first { screen in
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == requestedID
    }
    if selectedScreen != nil { break }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
} while ProcessInfo.processInfo.systemUptime < deadline
guard let screen = selectedScreen, let mode = CGDisplayCopyDisplayMode(requestedID),
      mode.pixelWidth == expectedWidth, mode.pixelHeight == expectedHeight else {
    emit(["stage": "error", "message": "Requested test display is missing or has unexpected physical dimensions"])
    exit(1)
}
let view = PatternView(frame: NSRect(origin: .zero, size: screen.frame.size), width: expectedWidth, height: expectedHeight)
if renderingMode == "layer-flush" {
    view.wantsLayer = true
    view.layerContentsRedrawPolicy = .onSetNeedsDisplay
    view.layer?.drawsAsynchronously = false
    view.layer?.contentsScale = screen.backingScaleFactor
}
let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
window.isReleasedWhenClosed = false
window.contentView = view
window.backgroundColor = .black
window.isOpaque = true
window.hasShadow = false
window.level = .screenSaver
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
window.ignoresMouseEvents = true
window.setFrame(screen.frame, display: true)
window.orderFrontRegardless()
view.display()
do { try view.saveReference(to: arguments[5]) } catch {
    emit(["stage": "error", "message": error.localizedDescription])
    exit(1)
}
view.display()
var metalRenderer: QualityMetalSource?
if renderingMode == "metal-display-link" {
    guard #available(macOS 14.0, *), let device = MTLCreateSystemDefaultDevice() else {
        emit(["stage": "error", "message": "Metal display link requires macOS 14 or newer and a Metal device"]); exit(1)
    }
    let metalView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
    let layer = CAMetalLayer()
    layer.device = device; layer.pixelFormat = .bgra8Unorm; layer.framebufferOnly = false
    layer.contentsScale = screen.backingScaleFactor; layer.maximumDrawableCount = 3
    layer.displaySyncEnabled = true; layer.presentsWithTransaction = false; layer.isOpaque = true
    layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    metalView.wantsLayer = true; metalView.layer = layer
    window.contentView = metalView
    layer.frame = metalView.bounds
    layer.drawableSize = CGSize(width: expectedWidth, height: expectedHeight)
    CATransaction.flush()
    do {
        metalRenderer = try MetalQualityRenderer(layer: layer, device: device,
                                                reference: URL(fileURLWithPath: arguments[5]),
                                                width: expectedWidth, height: expectedHeight, fps: fps)
    } catch { emit(["stage": "error", "message": error.localizedDescription]); exit(1) }
}
var ready: [String: Any] = ["stage": "ready", "displayId": requestedID, "renderingMode": renderingMode,
      "windowId": window.windowNumber,
      "physicalWidth": mode.pixelWidth, "physicalHeight": mode.pixelHeight,
      "logicalWidth": mode.width, "logicalHeight": mode.height,
      "actualRefreshRate": mode.refreshRate, "backingScaleFactor": screen.backingScaleFactor,
      "screenWidth": screen.frame.width, "screenHeight": screen.frame.height]
if let renderer = metalRenderer {
    ready["producer"] = "CAMetalDisplayLink"; ready["gpuName"] = renderer.gpuName
    ready["marker"] = renderer.marker; ready["referenceTextureOrigin"] = "top-left"
}
emit(ready)
var animationTimer: Timer?
if let renderer = metalRenderer { renderer.start() }
else {
    let timer = Timer(timeInterval: 1 / Double(fps), repeats: true) { _ in
        view.needsDisplay = true
        view.displayIfNeeded()
        if renderingMode == "layer-flush" {
            view.layer?.displayIfNeeded()
            CATransaction.flush()
        }
    }
    animationTimer = timer
    RunLoop.main.add(timer, forMode: .common)
}
let progress = Timer(timeInterval: 1, repeats: true) { _ in
    var stats: [String: Any] = ["stage": "pattern-progress", "draws": view.draws,
                              "elapsedSeconds": ProcessInfo.processInfo.systemUptime - view.epoch,
                              "renderingMode": renderingMode]
    if let renderer = metalRenderer { stats.merge(renderer.snapshot()) { _, new in new } }
    emit(stats)
}
RunLoop.main.add(progress, forMode: .common)
DispatchQueue.global(qos: .utility).async {
    _ = FileHandle.standardInput.readDataToEndOfFile()
    DispatchQueue.main.async {
        animationTimer?.invalidate(); progress.invalidate(); metalRenderer?.stop()
        window.close(); app.terminate(nil)
    }
}
app.run()
