// Original encoder-free source for separating GPU work from actual presentation.
// The marker matches capture-cadence-pattern.swift in physical, top-left pixels.
import AppKit
import CoreGraphics
import Foundation
import Metal
import QuartzCore

func output(_ value: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data + Data([10]))
    }
}

func distribution(_ values: [Double]) -> [String: Any] {
    guard !values.isEmpty else { return ["samples": 0] }
    let sorted = values.sorted()
    return ["samples": values.count, "meanMs": values.reduce(0, +) / Double(values.count),
            "p50Ms": sorted[sorted.count / 2],
            "p95Ms": sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))],
            "maxMs": sorted.last ?? 0]
}

func cadence(_ values: [Double]) -> [String: Any] {
    let sorted = values.sorted()
    guard sorted.count > 1, let first = sorted.first, let last = sorted.last, last > first else {
        return ["samples": sorted.count, "fps": 0]
    }
    var result = distribution(zip(sorted.dropFirst(), sorted).map { ($0 - $1) * 1000 })
    result["samples"] = sorted.count
    result["fps"] = Double(sorted.count - 1) / (last - first)
    return result
}

final class PresentationStats {
    let lock = NSLock()
    let epoch = ProcessInfo.processInfo.systemUptime
    var callbacks: UInt64 = 0
    var submitted: UInt64 = 0
    var completed: UInt64 = 0
    var presented: UInt64 = 0
    var zeroPresentedTimeCallbacks: UInt64 = 0
    var commandErrors: UInt64 = 0
    var drawableMisses: UInt64 = 0
    var displayLinkDeadlineMisses: UInt64 = 0
    var callbackTimes: [Double] = []
    var displayLinkTargetTimes: [Double] = []
    var displayLinkPresentationTargetTimes: [Double] = []
    var submittedTimes: [Double] = []
    var completedTimes: [Double] = []
    var presentedTimes: [Double] = []
    var gpuDurations: [Double] = []
    var drawableWaits: [Double] = []
    var presentedFrameIDs: Set<UInt16> = []
    var submittedFrameIDs: Set<UInt16> = []
    var completedSequences: Set<UInt64> = []
    var presentationSequences: Set<UInt64> = []
    var lastPresentedFrameID: UInt16 = 0
    var lastSubmittedFrameID: UInt16 = 0
    var lastError = ""

    func snapshot(stage: String, variant: String) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["stage": stage, "variant": variant,
                "elapsedSeconds": ProcessInfo.processInfo.systemUptime - epoch,
                "callbacks": callbacks, "submitted": submitted, "completed": completed,
                "presented": presented, "zeroPresentedTimeCallbacks": zeroPresentedTimeCallbacks,
                "presentationTimestampSupported": presented > 0,
                "presentationTimestampNote": "Positive presentedTime is required for presentation cadence. Virtual displays may report only zero timestamps even while captured frame markers advance; zero timestamps are not counted as drops.",
                "pendingPresentation": submitted - UInt64(presentationSequences.count),
                // A missing presentation callback is not proof of a dropped frame.
                "completedWithoutPresentationAtSnapshot": completedSequences.subtracting(presentationSequences).count,
                "commandErrors": commandErrors, "drawableMisses": drawableMisses,
                "displayLinkDeadlineMisses": displayLinkDeadlineMisses,
                "callbackCadence": cadence(callbackTimes),
                "displayLinkTargetCadence": cadence(displayLinkTargetTimes),
                "displayLinkPresentationTargetCadence": cadence(displayLinkPresentationTargetTimes),
                "uniqueSubmittedFrameIDs": submittedFrameIDs.count,
                "lastSubmittedFrameId": lastSubmittedFrameID,
                "uniquePresentedFrameIDs": presentedFrameIDs.count,
                "lastPresentedFrameId": lastPresentedFrameID,
                "submittedCadence": cadence(submittedTimes), "completedCadence": cadence(completedTimes),
                "presentedCadence": cadence(presentedTimes), "gpuDuration": distribution(gpuDurations),
                "nextDrawableWait": distribution(drawableWaits), "lastError": lastError]
    }
}

struct FrameParameters {
    var frameID: UInt32
    var width: UInt32
    var height: UInt32
    var reserved: UInt32 = 0
}

@available(macOS 14.0, *)
final class MetalDisplayLinkDriver: NSObject, CAMetalDisplayLinkDelegate {
    weak var source: MetalSource?
    let link: CAMetalDisplayLink

    init(source: MetalSource) {
        self.source = source
        link = CAMetalDisplayLink(metalLayer: source.layer)
        super.init()
        link.delegate = self
        let rate = Float(source.fps)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
    }

    func start() { link.add(to: .main, forMode: .common) }
    func stop() { link.invalidate() }

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        autoreleasepool {
            source?.renderDisplayLink(drawable: update.drawable, targetTimestamp: update.targetTimestamp,
                                      targetPresentationTimestamp: update.targetPresentationTimestamp)
        }
    }
}

final class MetalSource {
    let layer: CAMetalLayer
    let commandQueue: MTLCommandQueue
    let pipeline: MTLComputePipelineState
    let width: Int
    let height: Int
    let fps: Int
    let variant: String
    let stats = PresentationStats()
    let renderQueue = DispatchQueue(label: "cadence.metal.render", qos: .userInteractive)
    var timer: DispatchSourceTimer?
    var displayLinkDriver: AnyObject?
    var sequence: UInt64 = 0

    init(layer: CAMetalLayer, device: MTLDevice, width: Int, height: Int, fps: Int, variant: String) throws {
        self.layer = layer; self.width = width; self.height = height
        self.fps = fps; self.variant = variant
        guard let queue = device.makeCommandQueue() else {
            throw NSError(domain: "MetalCadence", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to create Metal command queue"])
        }
        commandQueue = queue
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct Parameters { uint frameID; uint width; uint height; uint reserved; };
        kernel void pattern(texture2d<float, access::write> target [[texture(0)]],
                            constant Parameters &p [[buffer(0)]], uint2 xy [[thread_position_in_grid]]) {
            if (xy.x >= p.width || xy.y >= p.height) return;
            float gray = (p.frameID & 1u) ? 0.84f : 0.16f;
            float4 color = float4(gray, gray, gray, 1.0f);
            uint movingX = (p.frameID % 120u) * (p.width - 160u) / 120u;
            if (xy.y >= 120u && xy.y < p.height - 40u && xy.x >= movingX && xy.x < movingX + 160u)
                color = float4(1.0f, 0.0f, 0.0f, 1.0f);
            if (xy.y < 96u) {
                color = float4(0.0f, 0.0f, 0.0f, 1.0f);
                if (xy.y >= 32u && xy.y < 64u) {
                    if (xy.x < 32u) color = float4(1.0f);
                    else if (xy.x < 544u) {
                        uint bit = (xy.x - 32u) / 32u;
                        if ((p.frameID & (1u << bit)) != 0u) color = float4(1.0f);
                    }
                }
            }
            target.write(color, xy);
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "pattern") else {
            throw NSError(domain: "MetalCadence", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Metal pattern function is missing"])
        }
        pipeline = try device.makeComputePipelineState(function: function)
    }

    func start() throws {
        if variant == "metal-display-link" {
            guard #available(macOS 14.0, *) else {
                throw NSError(domain: "MetalCadence", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "CAMetalDisplayLink requires macOS 14 or newer"])
            }
            let driver = MetalDisplayLinkDriver(source: self)
            displayLinkDriver = driver
            driver.start()
            return
        }
        let source = DispatchSource.makeTimerSource(queue: renderQueue)
        source.schedule(deadline: .now(), repeating: .nanoseconds(Int(1_000_000_000 / fps)),
                        leeway: .microseconds(100))
        source.setEventHandler { [weak self] in
            autoreleasepool { self?.render() }
        }
        timer = source
        source.resume()
    }

    func render() {
        stats.lock.lock()
        stats.callbacks += 1; stats.callbackTimes.append(CACurrentMediaTime())
        stats.lock.unlock()
        let waiting = ProcessInfo.processInfo.systemUptime
        let drawable = layer.nextDrawable()
        stats.lock.lock()
        stats.drawableWaits.append((ProcessInfo.processInfo.systemUptime - waiting) * 1000)
        if drawable == nil { stats.drawableMisses += 1 }
        stats.lock.unlock()
        guard let drawable else { return }
        submit(drawable: drawable)
    }

    func renderDisplayLink(drawable: CAMetalDrawable, targetTimestamp: Double, targetPresentationTimestamp: Double) {
        stats.lock.lock()
        stats.callbacks += 1; stats.callbackTimes.append(CACurrentMediaTime())
        stats.displayLinkTargetTimes.append(targetTimestamp)
        stats.displayLinkPresentationTargetTimes.append(targetPresentationTimestamp)
        stats.lock.unlock()
        submit(drawable: drawable, displayLinkDeadline: targetTimestamp)
    }

    func submit(drawable: CAMetalDrawable, displayLinkDeadline: Double? = nil) {
        guard let command = commandQueue.makeCommandBuffer(), let compute = command.makeComputeCommandEncoder() else {
            stats.lock.lock(); stats.commandErrors += 1
            stats.lastError = "Unable to allocate Metal command buffer/encoder"; stats.lock.unlock()
            return
        }
        sequence += 1
        let submittedSequence = sequence
        let frameID = UInt16(truncatingIfNeeded: submittedSequence)
        var parameters = FrameParameters(frameID: UInt32(frameID), width: UInt32(width), height: UInt32(height))
        compute.setComputePipelineState(pipeline)
        compute.setTexture(drawable.texture, index: 0)
        compute.setBytes(&parameters, length: MemoryLayout<FrameParameters>.stride, index: 0)
        let threadsWide = pipeline.threadExecutionWidth
        let threadsHigh = max(1, min(8, pipeline.maxTotalThreadsPerThreadgroup / threadsWide))
        compute.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: threadsWide, height: threadsHigh, depth: 1))
        compute.endEncoding()
        let metrics = stats
        drawable.addPresentedHandler { presentedDrawable in
            let time = presentedDrawable.presentedTime
            metrics.lock.lock(); defer { metrics.lock.unlock() }
            metrics.presentationSequences.insert(submittedSequence)
            if time > 0 && time.isFinite {
                metrics.presented += 1
                metrics.presentedTimes.append(time)
                metrics.presentedFrameIDs.insert(frameID)
                metrics.lastPresentedFrameID = frameID
            } else {
                // The controlled virtual-display test captured hundreds of
                // unique markers while every presentedTime callback was zero.
                // Zero is unavailable timestamp evidence here, not a drop count.
                metrics.zeroPresentedTimeCallbacks += 1
            }
        }
        command.addCompletedHandler { completedCommand in
            metrics.lock.lock(); defer { metrics.lock.unlock() }
            metrics.completed += 1
            metrics.completedSequences.insert(submittedSequence)
            metrics.completedTimes.append(ProcessInfo.processInfo.systemUptime)
            if completedCommand.status == .error {
                metrics.commandErrors += 1
                metrics.lastError = completedCommand.error?.localizedDescription ?? "Metal command failed"
            }
            let start = completedCommand.gpuStartTime
            let end = completedCommand.gpuEndTime
            if start > 0 && end >= start { metrics.gpuDurations.append((end - start) * 1000) }
        }
        stats.lock.lock()
        stats.submitted += 1; stats.submittedTimes.append(ProcessInfo.processInfo.systemUptime)
        stats.submittedFrameIDs.insert(frameID); stats.lastSubmittedFrameID = frameID
        stats.lock.unlock()
        if let deadline = displayLinkDeadline {
            // CAMetalDisplayLink supplies its drawable and presentation schedule.
            // Apple requires committing the GPU work before drawable.present();
            // timed present(at:) variants are invalid for this display link.
            // https://developer.apple.com/documentation/quartzcore/cametaldisplaylinkdelegate/metaldisplaylink(_:needsupdate:)
            command.commit()
            if CACurrentMediaTime() > deadline {
                stats.lock.lock(); stats.displayLinkDeadlineMisses += 1; stats.lock.unlock()
            }
            drawable.present()
        } else {
            command.present(drawable)
            command.commit()
        }
    }

    func stop(completion: @escaping () -> Void) {
        timer?.cancel(); timer = nil
        if #available(macOS 14.0, *), let driver = displayLinkDriver as? MetalDisplayLinkDriver { driver.stop() }
        displayLinkDriver = nil
        // Barrier runs after a possibly blocked nextDrawable call; main stays responsive.
        renderQueue.async { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: completion) }
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 6, let displayID = UInt32(arguments[1]),
      let width = Int(arguments[2]), let height = Int(arguments[3]), let fps = Int(arguments[4]),
      width >= 576, width <= 16384, height >= 240, height <= 16384,
      (1...240).contains(fps), ["metal-vsync", "metal-no-vsync", "metal-display-link"].contains(arguments[5]) else {
    fputs("Usage: capture-cadence-metal display-id physical-width physical-height fps metal-vsync|metal-no-vsync|metal-display-link\n", stderr)
    exit(2)
}
let variant = arguments[5]
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()
let deadline = ProcessInfo.processInfo.systemUptime + 10
var selectedScreen: NSScreen?
repeat {
    selectedScreen = NSScreen.screens.first {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
    }
    if selectedScreen != nil { break }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
} while ProcessInfo.processInfo.systemUptime < deadline
guard let screen = selectedScreen, let mode = CGDisplayCopyDisplayMode(displayID),
      mode.pixelWidth == width, mode.pixelHeight == height, let device = MTLCreateSystemDefaultDevice() else {
    output(["stage": "error", "message": "Owned test display dimensions or Metal device are unavailable"]); exit(1)
}
let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
window.isReleasedWhenClosed = false
let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
let layer = CAMetalLayer()
layer.device = device; layer.pixelFormat = .bgra8Unorm; layer.framebufferOnly = false
layer.drawableSize = CGSize(width: width, height: height)
layer.contentsScale = screen.backingScaleFactor
layer.maximumDrawableCount = 3; layer.allowsNextDrawableTimeout = true
layer.presentsWithTransaction = false; layer.displaySyncEnabled = variant != "metal-no-vsync"
layer.isOpaque = true; layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
view.wantsLayer = true; view.layer = layer
window.contentView = view
window.backgroundColor = .black; window.isOpaque = true; window.hasShadow = false
window.level = .screenSaver; window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
window.setFrame(screen.frame, display: true); window.orderFrontRegardless()
layer.frame = view.bounds
layer.drawableSize = CGSize(width: width, height: height)
CATransaction.flush()
guard (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID else {
    output(["stage": "error", "message": "Metal test window did not land on its owned display"]); window.close(); exit(1)
}
let source: MetalSource
do { source = try MetalSource(layer: layer, device: device, width: width, height: height, fps: fps, variant: variant) }
catch { output(["stage": "error", "message": error.localizedDescription]); window.close(); exit(1) }
output(["stage": "ready", "variant": variant, "displayId": displayID, "windowId": window.windowNumber,
        "physicalWidth": width, "physicalHeight": height, "logicalWidth": mode.width, "logicalHeight": mode.height,
        "actualRefreshRate": mode.refreshRate, "requestedFPS": fps, "gpuName": device.name,
        "producer": variant == "metal-display-link" ? "CAMetalDisplayLink" : "DispatchSourceTimer",
        "backingScaleFactor": screen.backingScaleFactor, "maximumFramesPerSecond": screen.maximumFramesPerSecond,
        "minimumRefreshInterval": screen.minimumRefreshInterval, "maximumRefreshInterval": screen.maximumRefreshInterval,
        "displayUpdateGranularity": screen.displayUpdateGranularity,
        "screenLastDisplayUpdateTimestamp": screen.lastDisplayUpdateTimestamp,
        "marker": ["bits": 16, "x": 48, "y": 48, "cell": 32, "whiteAnchorX": 16, "blackAnchorX": width - 16],
        "displaySyncEnabled": layer.displaySyncEnabled, "presentsWithTransaction": layer.presentsWithTransaction,
        "maximumDrawableCount": layer.maximumDrawableCount, "framebufferOnly": layer.framebufferOnly,
        "drawableWidth": layer.drawableSize.width, "drawableHeight": layer.drawableSize.height])
do { try source.start() }
catch { output(["stage": "error", "message": error.localizedDescription]); window.close(); exit(1) }
let statsTimer = Timer(timeInterval: 1, repeats: true) { _ in
    var snapshot = source.stats.snapshot(stage: "pattern-progress", variant: variant)
    snapshot["screenLastDisplayUpdateTimestamp"] = screen.lastDisplayUpdateTimestamp
    output(snapshot)
}
RunLoop.main.add(statsTimer, forMode: .common)
DispatchQueue.global(qos: .utility).async {
    _ = FileHandle.standardInput.readDataToEndOfFile()
    DispatchQueue.main.async {
        statsTimer.invalidate()
        source.stop {
            output(source.stats.snapshot(stage: "pattern-result", variant: variant))
            window.close()
            app.terminate(nil)
        }
    }
}
app.run()
