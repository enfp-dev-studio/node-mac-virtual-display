// Diagnostic only: counts capture cadence without encoding or saving images.
// Run only against an explicitly created test display and optional owned window.
import Foundation
import AppKit
import ScreenCaptureKit
import CoreGraphics
import CoreMedia
import CoreVideo
import IOSurface
import Darwin

private func emit(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
    FileHandle.standardOutput.write(data + Data([10]))
}

private struct ProbeError: Error {
    let message: String
}

private struct Options {
    let displayID: UInt32
    let width: Int
    let height: Int
    let fps: Int
    let duration: Double
    let warmup: Double
    let format: String
    let scope: String
    let windowID: UInt32?
    let queueDepth: Int
    let colorMode: String
    let backend: String
    let markerX: Int
    let markerY: Int
    let markerCell: Int
    let markerBits: Int
    let decodeMarker: Bool
    var pixelFormat: OSType { format == "bgra" ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange }

    init() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let allowed: Set<String> = ["--display-id", "--width", "--height", "--fps", "--duration", "--warmup", "--pixel-format", "--scope", "--window-id", "--queue-depth", "--color-mode", "--backend", "--marker-x", "--marker-y", "--marker-cell", "--marker-bits", "--decode-marker"]
        guard args.count.isMultiple(of: 2) else { throw ProbeError(message: "Expected flag/value argument pairs") }
        var values: [String: String] = [:]
        for index in stride(from: 0, to: args.count, by: 2) {
            guard allowed.contains(args[index]), values[args[index]] == nil else { throw ProbeError(message: "Unknown or duplicate argument: \(args[index])") }
            values[args[index]] = args[index + 1]
        }
        func integer(_ key: String, default fallback: Int? = nil, range: ClosedRange<Int>) throws -> Int {
            guard let raw = values[key] ?? fallback.map(String.init), let value = Int(raw), range.contains(value) else { throw ProbeError(message: "Invalid \(key)") }
            return value
        }
        func seconds(_ key: String, default fallback: Double, range: ClosedRange<Double>) throws -> Double {
            guard let value = Double(values[key] ?? String(fallback)), value.isFinite, range.contains(value) else { throw ProbeError(message: "Invalid \(key)") }
            return value
        }
        displayID = UInt32(try integer("--display-id", range: 1...Int(UInt32.max)))
        width = try integer("--width", range: 2...16384)
        height = try integer("--height", range: 2...16384)
        fps = try integer("--fps", default: 120, range: 0...240)
        duration = try seconds("--duration", default: 4, range: 0.5...60)
        warmup = try seconds("--warmup", default: 1, range: 0...20)
        format = values["--pixel-format"] ?? "nv12"
        scope = values["--scope"] ?? "display"
        colorMode = values["--color-mode"] ?? "reference"
        backend = values["--backend"] ?? "sck"
        queueDepth = try integer("--queue-depth", default: 4, range: 1...8)
        markerX = try integer("--marker-x", default: 48, range: 0...16383)
        markerY = try integer("--marker-y", default: 48, range: 0...16383)
        markerCell = try integer("--marker-cell", default: 32, range: 1...1024)
        markerBits = try integer("--marker-bits", default: 16, range: 1...32)
        let markerOption = values["--decode-marker"] ?? "true"
        guard ["true", "false"].contains(markerOption) else { throw ProbeError(message: "--decode-marker must be true or false") }
        decodeMarker = markerOption == "true"
        if values["--window-id"] != nil { windowID = UInt32(try integer("--window-id", range: 1...Int(UInt32.max))) }
        else { windowID = nil }
        guard ["nv12", "bgra"].contains(format), ["display", "window"].contains(scope),
              ["reference", "bt709"].contains(colorMode), ["sck", "cgdisplaystream"].contains(backend),
              scope != "window" || (windowID != nil && backend == "sck"),
              markerX + (markerBits - 1) * markerCell < width, markerY < height else { throw ProbeError(message: "Unsupported option combination or marker outside requested image") }
    }

    var metadata: [String: Any] {
        var result: [String: Any] = ["displayId": displayID, "width": width, "height": height, "captureFPS": fps,
            "duration": duration, "warmup": warmup, "pixelFormat": format, "scope": scope,
            "queueDepth": queueDepth, "colorMode": colorMode, "backend": backend,
            "markerDecodingEnabled": decodeMarker,
            "marker": ["x": markerX, "y": markerY, "cell": markerCell, "bits": markerBits, "endianness": "little"]]
        if let windowID { result["windowId"] = windowID }
        return result
    }
}

private struct Intervals {
    var last: Double?
    var deltas: [Double] = []
    var count = 0
    var repeated = 0
    var backwards = 0
    mutating func add(_ seconds: Double) {
        guard seconds.isFinite else { return }
        count += 1
        if let last {
            let delta = (seconds - last) * 1000
            if delta > 0 { deltas.append(delta) }
            else if delta == 0 { repeated += 1 }
            else { backwards += 1 }
        }
        last = seconds
    }
    var json: [String: Any] {
        let sorted = deltas.sorted()
        var bins: [String: Int] = [:]
        for value in deltas { bins[String(format: "%.1f", value), default: 0] += 1 }
        let common = bins.sorted { $0.value == $1.value ? (Double($0.key) ?? 0) < (Double($1.key) ?? 0) : $0.value > $1.value }.prefix(20).map { ["milliseconds": Double($0.key) ?? 0, "count": $0.value] as [String: Any] }
        func percentile(_ fraction: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))] }
        return ["samples": count, "positiveIntervals": deltas.count, "repeated": repeated, "backwards": backwards,
            "meanMs": deltas.isEmpty ? 0 : deltas.reduce(0, +) / Double(deltas.count),
            "minMs": sorted.first ?? 0, "p50Ms": percentile(0.5), "p95Ms": percentile(0.95),
            "p99Ms": percentile(0.99), "maxMs": sorted.last ?? 0, "histogram": common]
    }
}

private final class LinkRecorder {
    let lock = NSLock()
    var start = Double.infinity
    var end = -Double.infinity
    var intervals = Intervals()
    func record() {
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        lock.lock()
        if now >= start, now <= end { intervals.add(now) }
        lock.unlock()
    }
    func configure(start: Double, end: Double) {
        lock.lock(); self.start = start; self.end = end; lock.unlock()
    }
    func result(duration: Double) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["callbacks": intervals.count, "measuredFPS": Double(intervals.count) / duration, "wallIntervals": intervals.json]
    }
}

private let linkCallback: CVDisplayLinkOutputCallback = { _, _, _, _, _, context in
    guard let context else { return kCVReturnError }
    Unmanaged<LinkRecorder>.fromOpaque(context).takeUnretainedValue().record()
    return kCVReturnSuccess
}

private final class CadenceProbe: NSObject, SCStreamOutput, SCStreamDelegate {
    let options: Options
    let queue = DispatchQueue(label: "capture.cadence.probe", qos: .userInteractive)
    let displayInfo: [String: Any]
    var sckStream: SCStream?
    var cgStream: CGDisplayStream?
    var link: CVDisplayLink?
    let linkRecorder = LinkRecorder()
    var linkInfo: [String: Any] = [:]
    var start = Double.infinity
    var end = -Double.infinity
    var ready = false
    var finishing = false
    var statusCounts: [String: Int] = [:]
    var validSamples = 0
    var invalidSamples = 0
    var imageFrames = 0
    var completeImages = 0
    var formatMismatches = 0
    var validMarkers = 0
    var invalidMarkers = 0
    var frameIDs = Set<UInt32>()
    var sequence: [[String: Any]] = []
    var lastFrameID: UInt32?
    var changedIDs = 0
    var skippedIDs = 0
    var backwardsIDs = 0
    var ptsAll = Intervals()
    var ptsComplete = Intervals()
    var ptsIdle = Intervals()
    var displayTimes = Intervals()
    var completeDisplayTimes = Intervals()
    var wallAll = Intervals()
    var wallComplete = Intervals()
    var wallIdle = Intervals()
    var callbackCostMs = 0.0
    var maxCallbackCostMs = 0.0
    var callbacks = 0
    var timebase = mach_timebase_info_data_t()

    init(options: Options, displayInfo: [String: Any]) {
        self.options = options
        self.displayInfo = displayInfo
        super.init()
        mach_timebase_info(&timebase)
    }

    func begin() {
        queue.async {
            guard CGPreflightScreenCaptureAccess() else { self.fail("Screen Recording permission is required"); return }
            self.startDisplayLink()
            self.queue.asyncAfter(deadline: .now() + 15) { if !self.ready { self.fail("Capture startup exceeded 15 seconds") } }
            if self.options.backend == "cgdisplaystream" { self.startCGStream() }
            else { self.startSCK() }
        }
    }

    private func startDisplayLink() {
        var created: CVDisplayLink?
        let status = CVDisplayLinkCreateWithCGDisplay(options.displayID, &created)
        linkInfo["createStatus"] = status
        guard status == kCVReturnSuccess, let created else { return }
        link = created
        let nominal = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(created)
        if nominal.timeValue > 0 { linkInfo["nominalFPS"] = Double(nominal.timeScale) / Double(nominal.timeValue) }
        linkInfo["nominalFlags"] = nominal.flags
        let callbackStatus = CVDisplayLinkSetOutputCallback(created, linkCallback, Unmanaged.passUnretained(linkRecorder).toOpaque())
        linkInfo["callbackStatus"] = callbackStatus
        if callbackStatus == kCVReturnSuccess { linkInfo["startStatus"] = CVDisplayLinkStart(created) }
    }

    private func startSCK() {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            self.queue.async {
                guard !self.finishing else { return }
                if let error { self.fail(error.localizedDescription); return }
                guard let display = content?.displays.first(where: { $0.displayID == self.options.displayID }) else { self.fail("Explicit test display is missing from ScreenCaptureKit"); return }
                let filter: SCContentFilter
                if self.options.scope == "window" {
                    guard let window = content?.windows.first(where: { $0.windowID == self.options.windowID }), window.frame.intersects(CGDisplayBounds(self.options.displayID)) else { self.fail("Explicit test window is unavailable or outside the test display"); return }
                    filter = SCContentFilter(desktopIndependentWindow: window)
                } else { filter = SCContentFilter(display: display, excludingWindows: []) }
                let config = SCStreamConfiguration()
                config.width = self.options.width
                config.height = self.options.height
                config.minimumFrameInterval = self.options.fps == 0 ? .zero : CMTime(value: 1, timescale: CMTimeScale(self.options.fps))
                config.pixelFormat = self.options.pixelFormat
                config.showsCursor = false
                config.capturesAudio = false
                config.scalesToFit = false
                config.backgroundColor = .clear
                config.queueDepth = self.options.queueDepth
                if self.options.colorMode == "bt709" {
                    config.colorSpaceName = CGColorSpace.itur_709
                    config.colorMatrix = kCVImageBufferYCbCrMatrix_ITU_R_709_2
                }
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                do { try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue) }
                catch { self.fail(error.localizedDescription); return }
                self.sckStream = stream
                stream.startCapture { error in
                    self.queue.async {
                        if let error { self.fail(error.localizedDescription) }
                        else { self.didStart() }
                    }
                }
            }
        }
    }

    private func startCGStream() {
        var properties: [CFString: Any] = [CGDisplayStream.showCursor: false]
        if options.fps > 0 { properties[CGDisplayStream.minimumFrameTime] = 1 / Double(options.fps) }
        if options.colorMode == "bt709", let colorSpace = CGColorSpace(name: CGColorSpace.itur_709) { properties[CGDisplayStream.colorSpace] = colorSpace }
        guard let stream = CGDisplayStream(dispatchQueueDisplay: options.displayID, outputWidth: options.width,
            outputHeight: options.height, pixelFormat: Int32(bitPattern: options.pixelFormat),
            properties: properties as CFDictionary, queue: queue, handler: { [weak self] status, displayTime, surface, _ in
                guard let self else { return }
                let entered = DispatchTime.now().uptimeNanoseconds
                let label: String
                switch status {
                case .frameComplete: label = "complete"
                case .frameIdle: label = "idle"
                case .frameBlank: label = "blank"
                case .stopped: label = "stopped"
                @unknown default: label = "unknown"
                }
                var pixelBuffer: CVPixelBuffer?
                if let surface {
                    var wrapped: Unmanaged<CVPixelBuffer>?
                    if CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, nil, &wrapped) == kCVReturnSuccess { pixelBuffer = wrapped?.takeRetainedValue() }
                }
                let timestamp = self.machSeconds(displayTime)
                self.record(status: label, pts: timestamp, displayTime: timestamp, pixelBuffer: pixelBuffer, entered: entered, valid: true)
            }) else { fail("CGDisplayStream could not be created on this macOS version"); return }
        cgStream = stream
        let status = stream.start()
        if status == .success { didStart() }
        else { fail("CGDisplayStream start failed: \(status.rawValue)") }
    }

    private func didStart() {
        guard !ready, !finishing else { return }
        ready = true
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        start = now + options.warmup
        end = start + options.duration
        linkRecorder.configure(start: start, end: end)
        var result = options.metadata
        result.merge(["stage": "ready", "display": displayInfo, "cvDisplayLink": linkInfo]) { _, new in new }
        emit(result)
        queue.asyncAfter(deadline: .now() + options.warmup + options.duration) { self.finish() }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { queue.async { if !self.finishing { self.fail(error.localizedDescription) } } }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        let entered = DispatchTime.now().uptimeNanoseconds
        guard type == .screen else { return }
        let attachments = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first
        let raw = (attachments?[.status] as? NSNumber)?.intValue
        let status = raw.flatMap(SCFrameStatus.init(rawValue:))
        let label: String
        switch status {
        case .complete: label = "complete"
        case .idle: label = "idle"
        case .blank: label = "blank"
        case .suspended: label = "suspended"
        case .started: label = "started"
        case .stopped: label = "stopped"
        default: label = "unknown"
        }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let pts = timestamp.isValid && timestamp.isNumeric ? CMTimeGetSeconds(timestamp) : nil
        let displayTime = (attachments?[.displayTime] as? NSNumber).map { machSeconds($0.uint64Value) }
        record(status: label, pts: pts, displayTime: displayTime,
            pixelBuffer: CMSampleBufferGetImageBuffer(sampleBuffer), entered: entered, valid: sampleBuffer.isValid)
    }

    private func machSeconds(_ ticks: UInt64) -> Double { Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000 }

    private func record(status: String, pts: Double?, displayTime: Double?, pixelBuffer: CVPixelBuffer?, entered: UInt64, valid: Bool) {
        let now = Double(entered) / 1_000_000_000
        guard !finishing, now >= start, now <= end else { return }
        callbacks += 1
        statusCounts[status, default: 0] += 1
        wallAll.add(now)
        if valid { validSamples += 1 } else { invalidSamples += 1 }
        if let pts { ptsAll.add(pts) }
        if let displayTime { displayTimes.add(displayTime) }
        if status == "complete" {
            wallComplete.add(now)
            if let pts { ptsComplete.add(pts) }
            if let displayTime { completeDisplayTimes.add(displayTime) }
        } else if status == "idle" {
            wallIdle.add(now)
            if let pts { ptsIdle.add(pts) }
        }
        if let pixelBuffer {
            imageFrames += 1
            if status == "complete" { completeImages += 1 }
            if CVPixelBufferGetWidth(pixelBuffer) != options.width || CVPixelBufferGetHeight(pixelBuffer) != options.height || CVPixelBufferGetPixelFormatType(pixelBuffer) != options.pixelFormat { formatMismatches += 1 }
            else if status == "complete", options.decodeMarker, let id = readMarker(pixelBuffer) {
                validMarkers += 1
                frameIDs.insert(id)
                if let previous = lastFrameID, id != previous {
                    changedIDs += 1
                    if id > previous + 1 { skippedIDs += Int(id - previous - 1) }
                    if id < previous { backwardsIDs += 1 }
                }
                lastFrameID = id
                if sequence.count < 128 { sequence.append(["frameId": id, "wallSeconds": now - start, "ptsSeconds": pts ?? -1]) }
            } else if status == "complete", options.decodeMarker { invalidMarkers += 1 }
        }
        let cost = Double(DispatchTime.now().uptimeNanoseconds - entered) / 1_000_000
        callbackCostMs += cost
        maxCallbackCostMs = max(maxCallbackCostMs, cost)
    }

    private func readMarker(_ pixelBuffer: CVPixelBuffer) -> UInt32? {
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let planar = CVPixelBufferIsPlanar(pixelBuffer)
        guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) : CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let rowBytes = planar ? CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) : CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        func brightness(_ x: Int, _ y: Int) -> Int {
            if planar { return Int(bytes[y * rowBytes + x]) }
            let offset = y * rowBytes + x * 4
            return (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
        }
        let white = brightness(16, options.markerY)
        let black = brightness(options.width - 16, options.markerY)
        guard white >= 180, black <= 70, white - black >= 120 else { return nil }
        let threshold = (white + black) / 2
        var result: UInt32 = 0
        for bit in 0..<options.markerBits {
            if brightness(options.markerX + bit * options.markerCell, options.markerY) > threshold { result |= UInt32(1) << UInt32(bit) }
        }
        return result
    }

    private func finish() {
        guard !finishing else { return }
        finishing = true
        if let link {
            let actual = CVDisplayLinkGetActualOutputVideoRefreshPeriod(link)
            if actual > 0, actual.isFinite { linkInfo["actualPeriodFPS"] = 1 / actual }
            CVDisplayLinkStop(link)
        }
        let complete = statusCounts["complete"] ?? 0
        var result = options.metadata
        result.merge(["stage": "result", "display": displayInfo, "measurementSeconds": options.duration,
            "callbacks": callbacks, "callbackFPS": Double(callbacks) / options.duration, "statuses": statusCounts,
            "validSamples": validSamples, "invalidSamples": invalidSamples,
            "completeFPS": Double(complete) / options.duration, "imageFrames": imageFrames,
            "imageFPS": Double(imageFrames) / options.duration, "completeImages": completeImages,
            "formatMismatches": formatMismatches, "validMarkers": validMarkers, "invalidMarkers": invalidMarkers,
            "uniqueFrameIds": options.decodeMarker ? frameIDs.count as Any : NSNull(),
            "uniqueFPS": options.decodeMarker ? Double(frameIDs.count) / options.duration as Any : NSNull(),
            "changedFrameIds": changedIDs, "skippedFrameIds": skippedIDs, "backwardsFrameIds": backwardsIDs,
            "sampleFrameIds": sequence, "ptsAll": ptsAll.json, "ptsComplete": ptsComplete.json, "ptsIdle": ptsIdle.json,
            "displayTimeAll": displayTimes.json, "displayTimeComplete": completeDisplayTimes.json,
            "wallAll": wallAll.json, "wallComplete": wallComplete.json, "wallIdle": wallIdle.json,
            "callbackCost": ["meanMs": callbacks > 0 ? callbackCostMs / Double(callbacks) : 0, "maxMs": maxCallbackCostMs],
            "cvDisplayLink": linkInfo.merging(linkRecorder.result(duration: options.duration)) { _, new in new }
        ]) { _, new in new }
        let completeFinish = { emit(result); Darwin.exit(0) }
        if let sckStream { sckStream.stopCapture { _ in self.queue.async { completeFinish() } } }
        else { _ = cgStream?.stop(); completeFinish() }
        queue.asyncAfter(deadline: .now() + 3) { completeFinish() }
    }

    private func fail(_ message: String) {
        emit(["stage": "error", "message": message, "backend": options.backend])
        Darwin.exit(1)
    }
}

do {
    let options = try Options()
    guard let mode = CGDisplayCopyDisplayMode(options.displayID), mode.pixelWidth == options.width, mode.pixelHeight == options.height else { throw ProbeError(message: "Explicit test display is unavailable or physical dimensions differ") }
    var display: [String: Any] = ["displayId": options.displayID, "cgRefreshRate": mode.refreshRate,
        "cgWidth": mode.width, "cgHeight": mode.height, "cgPixelWidth": mode.pixelWidth, "cgPixelHeight": mode.pixelHeight,
        "online": CGDisplayIsOnline(options.displayID) > 0, "active": CGDisplayIsActive(options.displayID) > 0]
    if let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == options.displayID }) {
        display["nsScreen"] = ["maximumFramesPerSecond": screen.maximumFramesPerSecond,
            "minimumRefreshInterval": screen.minimumRefreshInterval, "maximumRefreshInterval": screen.maximumRefreshInterval,
            "displayUpdateGranularity": screen.displayUpdateGranularity, "lastDisplayUpdateTimestamp": screen.lastDisplayUpdateTimestamp,
            "backingScaleFactor": screen.backingScaleFactor, "width": screen.frame.width, "height": screen.frame.height]
    }
    let probe = CadenceProbe(options: options, displayInfo: display)
    probe.begin()
    withExtendedLifetime(probe) { dispatchMain() }
} catch {
    emit(["stage": "error", "message": (error as? ProbeError)?.message ?? error.localizedDescription])
    exit(2)
}
