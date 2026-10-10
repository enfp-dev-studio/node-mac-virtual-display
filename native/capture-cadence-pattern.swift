// Encoder-free source fixture for diagnosing render -> compositor -> capture
// cadence. Every variant draws the same physical-pixel binary frame marker.
import AppKit
import CoreGraphics
import Foundation
import QuartzCore

func output(_ value: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data + Data([10]))
    }
}

final class CadenceView: NSView {
    let physicalWidth: Int
    let physicalHeight: Int
    let heavy: Bool
    let epoch = ProcessInfo.processInfo.systemUptime
    var drawCount: UInt64 = 0
    var drawTimes: [Double] = []
    var drawDurations: [Double] = []
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    init(frame: NSRect, width: Int, height: Int, heavy: Bool) {
        physicalWidth = width; physicalHeight = height; self.heavy = heavy
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let started = ProcessInfo.processInfo.systemUptime
        drawCount += 1
        drawTimes.append(started)
        let scaleX = bounds.width / CGFloat(physicalWidth)
        let scaleY = bounds.height / CGFloat(physicalHeight)
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
            color.setFill()
            NSRect(x: x * scaleX, y: y * scaleY, width: w * scaleX, height: h * scaleY).fill()
        }
        let width = CGFloat(physicalWidth)
        let height = CGFloat(physicalHeight)
        // Changes cover almost the whole test window on every real draw. Even
        // when a compositor skips every second update, the marker identifies it.
        rect(0, 0, width, height, NSColor(white: drawCount.isMultiple(of: 2) ? 0.16 : 0.84, alpha: 1))
        let movingX = CGFloat(drawCount % 120) / 120 * max(1, width - 160)
        rect(movingX, 120, 160, max(1, height - 160), .red)
        if heavy {
            // Similar workload to the earlier checker/text reference fixture,
            // confined below the diagnostic marker so decoding stays identical.
            let columns = Int(Double(physicalWidth) * 0.42 / 8)
            let rows = Int(Double(physicalHeight) * 0.25 / 8)
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    rect(64 + CGFloat(column * 8), height * 0.64 + CGFloat(row * 8), 8, 8, .black)
                }
            }
            ("HEVC 0123456789 | HiDPI AaBbMmWw" as NSString).draw(
                at: NSPoint(x: 0.05 * bounds.width, y: 0.19 * bounds.height),
                withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: bounds.height * 0.043, weight: .regular),
                                 .foregroundColor: NSColor.black])
        }
        // Physical marker: top-left origin, 16 little-endian bits. Cell centers
        // are (48 + bit*32, 48); white/black guard centers are (16,48)/(W-16,48).
        rect(0, 0, width, 96, .black)
        rect(0, 32, 32, 32, .white)
        for bit in 0..<16 where (drawCount & (UInt64(1) << UInt64(bit))) != 0 {
            rect(32 + CGFloat(bit * 32), 32, 32, 32, .white)
        }
        drawDurations.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
        if drawTimes.count > 10000 { drawTimes.removeFirst(1000) }
        if drawDurations.count > 10000 { drawDurations.removeFirst(1000) }
    }
}

final class RenderDriver: NSObject {
    let view: CadenceView
    let window: NSWindow
    let variant: String
    var callbacks = 0
    var callbackTimes: [Double] = []
    var flushCalls = 0
    var transactionFlushCalls = 0
    var displayLinkTimestamps: [Double] = []
    var displayLinkDurations: [Double] = []
    var lastDisplayLinkTargetTimestamp = 0.0
    init(view: CadenceView, window: NSWindow, variant: String) {
        self.view = view; self.window = window; self.variant = variant
    }
    func render() {
        callbacks += 1
        callbackTimes.append(ProcessInfo.processInfo.systemUptime)
        view.needsDisplay = true
        view.displayIfNeeded()
        if variant == "timer-window-flush" {
            // Intentionally exercise the deprecated API as a diagnostic only.
            window.flush()
            flushCalls += 1
        }
        if variant == "timer-layer-flush" {
            view.layer?.displayIfNeeded()
        }
        if variant == "timer-layer-flush" || variant == "timer-transaction-flush" {
            CATransaction.flush()
            transactionFlushCalls += 1
        }
        if callbackTimes.count > 10000 { callbackTimes.removeFirst(1000) }
    }
    @available(macOS 14.0, *)
    @objc func displayLinkFired(_ sender: CADisplayLink) {
        displayLinkTimestamps.append(sender.timestamp)
        displayLinkDurations.append(sender.duration)
        lastDisplayLinkTargetTimestamp = sender.targetTimestamp
        if displayLinkTimestamps.count > 10000 { displayLinkTimestamps.removeFirst(1000) }
        if displayLinkDurations.count > 10000 { displayLinkDurations.removeFirst(1000) }
        render()
    }
}

func cadence(_ times: [Double]) -> [String: Any] {
    guard times.count >= 2, let first = times.first, let last = times.last, last > first else {
        return ["samples": times.count, "fps": 0]
    }
    let gaps = zip(times.dropFirst(), times).map { ($0 - $1) * 1000 }.sorted()
    return ["samples": times.count, "fps": Double(times.count - 1) / (last - first),
            "p50Ms": gaps[gaps.count / 2], "p95Ms": gaps[min(gaps.count - 1, Int(Double(gaps.count) * 0.95))],
            "maxMs": gaps.last ?? 0]
}

let arguments = CommandLine.arguments
let allowed: Set<String> = ["timer-default", "timer-window-flush", "timer-layer-default", "timer-layer-flush", "timer-transaction-flush", "display-link", "timer-heavy"]
guard arguments.count == 6, let displayID = UInt32(arguments[1]),
      let width = Int(arguments[2]), let height = Int(arguments[3]),
      let fps = Int(arguments[4]), width >= 576, height >= 240,
      (1...240).contains(fps), allowed.contains(arguments[5]) else {
    fputs("Usage: capture-cadence-pattern display-id physical-width physical-height fps timer-default|timer-window-flush|timer-layer-default|timer-layer-flush|timer-transaction-flush|display-link|timer-heavy\n", stderr)
    exit(2)
}
let variant = arguments[5]
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()
let deadline = ProcessInfo.processInfo.systemUptime + 10
var selectedScreen: NSScreen?
repeat {
    selectedScreen = NSScreen.screens.first { screen in
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
    }
    if selectedScreen != nil { break }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
} while ProcessInfo.processInfo.systemUptime < deadline
guard let screen = selectedScreen, let mode = CGDisplayCopyDisplayMode(displayID),
      mode.pixelWidth == width, mode.pixelHeight == height else {
    output(["stage": "error", "message": "Requested owned test display is missing or has unexpected dimensions"])
    exit(1)
}
let view = CadenceView(frame: NSRect(origin: .zero, size: screen.frame.size), width: width, height: height, heavy: variant == "timer-heavy")
if variant == "timer-layer-flush" || variant == "timer-layer-default" {
    view.wantsLayer = true
    view.layerContentsRedrawPolicy = .onSetNeedsDisplay
    view.layer?.drawsAsynchronously = false
    view.layer?.contentsScale = screen.backingScaleFactor
}
let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
window.contentView = view
window.backgroundColor = .black; window.isOpaque = true; window.hasShadow = false
window.level = .screenSaver
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
window.ignoresMouseEvents = true
window.setFrame(screen.frame, display: true)
window.orderFrontRegardless()
view.display()
let driver = RenderDriver(view: view, window: window, variant: variant)
var animationTimer: Timer?
var displayLink: AnyObject?
if variant == "display-link" {
    guard #available(macOS 14.0, *) else {
        output(["stage": "error", "message": "NSScreen display link requires macOS 14 or newer"]); exit(1)
    }
    let link = screen.displayLink(target: driver, selector: #selector(RenderDriver.displayLinkFired(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: Float(fps), maximum: Float(fps), preferred: Float(fps))
    link.add(to: .main, forMode: .common)
    displayLink = link
} else {
    animationTimer = Timer(timeInterval: 1 / Double(fps), repeats: true) { _ in driver.render() }
    RunLoop.main.add(animationTimer!, forMode: .common)
}
output(["stage": "ready", "variant": variant, "displayId": displayID, "windowId": window.windowNumber,
        "processId": ProcessInfo.processInfo.processIdentifier,
        "physicalWidth": width, "physicalHeight": height, "logicalWidth": mode.width, "logicalHeight": mode.height,
        "actualRefreshRate": mode.refreshRate, "requestedFPS": fps,
        "backingScaleFactor": screen.backingScaleFactor, "maximumFramesPerSecond": screen.maximumFramesPerSecond,
        "minimumRefreshInterval": screen.minimumRefreshInterval, "maximumRefreshInterval": screen.maximumRefreshInterval,
        "displayUpdateGranularity": screen.displayUpdateGranularity,
        "screenLastDisplayUpdateTimestamp": screen.lastDisplayUpdateTimestamp,
        "marker": ["bits": 16, "x": 48, "y": 48, "cell": 32, "whiteAnchorX": 16, "blackAnchorX": width - 16],
        "isLayerBacked": view.layer != nil, "backingType": window.backingType.rawValue])
let statsTimer = Timer(timeInterval: 1, repeats: true) { _ in
    let elapsed = ProcessInfo.processInfo.systemUptime - view.epoch
    let durationSum = view.drawDurations.reduce(0, +)
    output(["stage": "pattern-progress", "variant": variant, "elapsedSeconds": elapsed,
            "draws": view.drawCount, "frameId": view.drawCount & 65535, "callbacks": driver.callbacks,
            "drawCadence": cadence(view.drawTimes), "callbackCadence": cadence(driver.callbackTimes),
            "drawMeanMs": view.drawDurations.isEmpty ? 0 : durationSum / Double(view.drawDurations.count),
            "drawMaxMs": view.drawDurations.max() ?? 0,
            "flushCalls": driver.flushCalls, "transactionFlushCalls": driver.transactionFlushCalls,
            "displayLinkCadence": cadence(driver.displayLinkTimestamps),
            "displayLinkDurationMs": (driver.displayLinkDurations.last ?? 0) * 1000,
            "displayLinkTargetTimestamp": driver.lastDisplayLinkTargetTimestamp,
            "screenLastDisplayUpdateTimestamp": screen.lastDisplayUpdateTimestamp])
}
RunLoop.main.add(statsTimer, forMode: .common)
DispatchQueue.global(qos: .utility).async {
    _ = FileHandle.standardInput.readDataToEndOfFile()
    DispatchQueue.main.async {
        animationTimer?.invalidate()
        if #available(macOS 14.0, *), let link = displayLink as? CADisplayLink { link.invalidate() }
        app.terminate(nil)
    }
}
app.run()
