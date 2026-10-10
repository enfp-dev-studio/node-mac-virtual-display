// Independent comparison driver. The harness compiles this alongside an
// UNMODIFIED SideScreen VideoEncoder.swift supplied by --baseline-reference.
// Configuration and cached-buffer behavior reproduce the inspected reference.
import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

enum StreamCodec { case hevc, h264 }
func debugLog(_ message: String) { fputs(message + "\n", stderr) }
func output(_ object: [String: Any]) {
    if let bytes = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(bytes + Data([10]))
    }
}

final class ReferenceDriver: NSObject, SCStreamOutput, SCStreamDelegate {
    let displayID: CGDirectDisplayID
    let width: Int
    let height: Int
    let fps: Int
    let duration: Double
    let warmup: Double
    let encodeQueue = DispatchQueue(label: "reference.encode", qos: .userInteractive)
    let lock = NSLock()
    var encoder: VideoEncoder?
    var stream: SCStream?
    var lastPixelBuffer: CVPixelBuffer?
    var pending = 0
    var measurementStart = Double.infinity
    var callbacks = 0
    var completeFrames = 0
    var imageFrames = 0
    var replayedFrames = 0
    var skippedFrames = 0
    var encodedFrames = 0
    var encodedBytes = 0
    var keyframes = 0
    var totalEncodeMs = 0.0
    var maxEncodeMs = 0.0
    var statuses: [String: Int] = [:]
    let bitstream: FileHandle
    let timelinePath: String?
    let nativeInterval: Bool
    var encodedTimeline: [[String: Any]] = []

    init(displayID: UInt32, width: Int, height: Int, fps: Int, duration: Double, warmup: Double, bitstream: FileHandle, timelinePath: String? = nil, nativeInterval: Bool = false) {
        self.displayID = displayID; self.width = width; self.height = height
        self.fps = fps; self.duration = duration; self.warmup = warmup; self.bitstream = bitstream
        self.timelinePath = timelinePath
        self.nativeInterval = nativeInterval
    }
    var measuring: Bool {
        let elapsed = ProcessInfo.processInfo.systemUptime - measurementStart
        return elapsed >= 0 && elapsed < duration
    }

    func start() {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
            guard let display = content?.displays.first(where: { $0.displayID == self.displayID }) else {
                self.fail(error?.localizedDescription ?? "Own test display is unavailable"); return
            }
            self.encoder = VideoEncoder(width: self.width, height: self.height, codec: .hevc,
                                        bitrateMbps: 60, quality: "ultralow", gamingBoost: false, frameRate: self.fps)
            self.encoder?.onEncodedFrame = { data, timestamp, keyframe in
                self.lock.lock()
                let measured = self.measuring
                if self.timelinePath != nil {
                    self.encodedTimeline.append(["measured": measured,
                        "wallSeconds": ProcessInfo.processInfo.systemUptime,
                        "measurementSeconds": self.measurementStart.isFinite ? (ProcessInfo.processInfo.systemUptime - self.measurementStart) as Any : NSNull(),
                        "captureNanos": timestamp, "keyFrame": keyframe])
                }
                if measured {
                    let latencyMs = Double(DispatchTime.now().uptimeNanoseconds - timestamp) / 1_000_000
                    self.encodedFrames += 1; self.encodedBytes += data.count
                    self.keyframes += keyframe ? 1 : 0
                    self.totalEncodeMs += latencyMs; self.maxEncodeMs = max(self.maxEncodeMs, latencyMs)
                }
                self.bitstream.write(data)
                self.lock.unlock()
            }
            let config = SCStreamConfiguration()
            config.width = self.width; config.height = self.height
            config.minimumFrameInterval = self.nativeInterval ? .zero : CMTime(value: 1, timescale: CMTimeScale(self.fps))
            config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            config.showsCursor = true; config.queueDepth = 4; config.capturesAudio = false
            config.backgroundColor = .clear; config.scalesToFit = false
            let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
            self.stream = stream
            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
                stream.startCapture { error in
                    if let error { self.fail(error.localizedDescription); return }
                    self.lock.lock()
                    self.measurementStart = ProcessInfo.processInfo.systemUptime + self.warmup
                    self.lock.unlock()
                    output(["stage": "baseline-ready", "width": self.width, "height": self.height, "fps": self.fps])
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.duration + self.warmup) { self.stop() }
                }
            } catch { self.fail(error.localizedDescription) }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let image = CMSampleBufferGetImageBuffer(sample)
        let attachment = (CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first
        let status = (attachment?[.status] as? NSNumber)?.stringValue ?? "missing"
        lock.lock()
        let measured = measuring
        if measured {
            callbacks += 1; statuses[status, default: 0] += 1
            if status == String(SCFrameStatus.complete.rawValue) { completeFrames += 1 }
            if image != nil { imageFrames += 1 }
        }
        if pending >= 2 {
            if measured { skippedFrames += 1 }
            lock.unlock(); return
        }
        let buffer: CVPixelBuffer?
        if let image { lastPixelBuffer = image; buffer = image }
        else { buffer = lastPixelBuffer; if measured && buffer != nil { replayedFrames += 1 } }
        guard let buffer else { lock.unlock(); return }
        pending += 1
        lock.unlock()
        encodeQueue.async {
            self.encoder?.encode(pixelBuffer: buffer, presentationTimeStamp: pts)
            self.lock.lock(); self.pending -= 1; self.lock.unlock()
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { fail(error.localizedDescription) }
    func fail(_ message: String) { output(["stage": "baseline-error", "message": message]); exit(1) }
    func stop() {
        stream?.stopCapture { error in
            if let error { self.fail(error.localizedDescription); return }
            self.encodeQueue.async {
                self.encoder = nil
                self.lock.lock()
                if let timelinePath = self.timelinePath {
                    do {
                        let data = try JSONSerialization.data(withJSONObject: self.encodedTimeline, options: [.sortedKeys])
                        try data.write(to: URL(fileURLWithPath: timelinePath))
                    } catch { self.fail("Unable to save reference timeline: \(error.localizedDescription)") }
                }
                output(["stage": "baseline-result", "seconds": self.duration,
                        "minimumFrameIntervalMode": self.nativeInterval ? "native-refresh-override" : "reference-original-fixed",
                        "callbacks": self.callbacks, "callbackFps": Double(self.callbacks) / self.duration,
                        "completeFrames": self.completeFrames, "completeFps": Double(self.completeFrames) / self.duration,
                        "imageFrames": self.imageFrames, "replayedFrames": self.replayedFrames,
                        "skippedFrames": self.skippedFrames, "encodedFrames": self.encodedFrames,
                        "encodedFps": Double(self.encodedFrames) / self.duration,
                        "bitrateMbps": Double(self.encodedBytes) * 8 / self.duration / 1_000_000,
                        "keyframes": self.keyframes,
                        "meanEncodeMs": self.encodedFrames > 0 ? self.totalEncodeMs / Double(self.encodedFrames) : 0,
                        "maxEncodeMs": self.maxEncodeMs, "statuses": self.statuses])
                self.bitstream.closeFile(); self.lock.unlock()
                exit(0)
            }
        }
    }
}

let arguments = CommandLine.arguments
guard (8...10).contains(arguments.count), let displayID = UInt32(arguments[1]), let width = Int(arguments[2]),
      let height = Int(arguments[3]), let fps = Int(arguments[4]), let duration = Double(arguments[5]),
      let warmup = Double(arguments[6]), (2...30).contains(duration), (0...10).contains(warmup) else {
    fputs("Usage: reference-baseline display-id width height fps duration warmup stream.h265 [timeline.json [fixed|native]]\n", stderr); exit(2)
}
FileManager.default.createFile(atPath: arguments[7], contents: nil)
guard let file = FileHandle(forWritingAtPath: arguments[7]) else { exit(1) }
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
guard arguments.count < 10 || ["fixed", "native"].contains(arguments[9]) else { exit(2) }
let driver = ReferenceDriver(displayID: displayID, width: width, height: height, fps: fps, duration: duration, warmup: warmup, bitstream: file, timelinePath: arguments.count >= 9 ? arguments[8] : nil, nativeInterval: arguments.count == 10 && arguments[9] == "native")
driver.start()
DispatchQueue.main.asyncAfter(deadline: .now() + duration + warmup + 20) { driver.fail("Reference capture exceeded overall deadline") }
application.run()
