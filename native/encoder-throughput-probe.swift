// Encoder-only diagnostic. Compile this as main.swift alongside the UNMODIFIED
// SideScreen MacHost/Sources/VideoEncoder.swift. No screen/window is captured.
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

enum StreamCodec { case hevc, h264 }
func debugLog(_ message: String) { fputs(message + "\n", stderr) }
func emit(_ value: [String: Any]) {
    if let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(bytes + Data([10]))
    }
}

struct Options {
    let width: Int
    let height: Int
    let fps: Int
    let duration: Double
    let warmup: Double
    let maximumOutstanding: Int
    let poolSize: Int
    let outputPath: String?
    init() throws {
        var values: [String: String] = [:]
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count.isMultiple(of: 2) else { throw Failure("Expected --name value pairs") }
        let known: Set<String> = ["--width", "--height", "--fps", "--duration", "--warmup", "--max-outstanding", "--pool-size", "--output"]
        for index in stride(from: 0, to: args.count, by: 2) {
            guard known.contains(args[index]), values[args[index]] == nil else { throw Failure("Unknown or duplicate option: \(args[index])") }
            values[args[index]] = args[index + 1]
        }
        func number(_ key: String, _ fallback: Int, _ range: ClosedRange<Int>) throws -> Int {
            guard let value = Int(values[key] ?? String(fallback)), range.contains(value) else { throw Failure("Invalid \(key)") }
            return value
        }
        func decimal(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) throws -> Double {
            guard let value = Double(values[key] ?? String(fallback)), value.isFinite, range.contains(value) else { throw Failure("Invalid \(key)") }
            return value
        }
        width = try number("--width", 1280, 64...3840)
        height = try number("--height", 720, 64...2160)
        fps = try number("--fps", 120, 1...240)
        duration = try decimal("--duration", 6, 2...30)
        warmup = try decimal("--warmup", 1, 0...10)
        maximumOutstanding = try number("--max-outstanding", 3, 0...256)
        poolSize = try number("--pool-size", 64, 4...128)
        outputPath = values["--output"]
        guard width.isMultiple(of: 2), height.isMultiple(of: 2), width * height * poolSize * 3 / 2 <= 256 * 1024 * 1024 else {
            throw Failure("NV12 dimensions must be even and the immutable source pool must fit 256 MiB")
        }
    }
    var json: [String: Any] {
        ["width": width, "height": height, "fps": fps, "duration": duration, "warmup": warmup,
         "maximumOutstanding": maximumOutstanding, "poolSize": poolSize,
         "codec": "hevc", "bitrate": 60_000_000, "quality": "ultralow", "pacing": "strict-dispatch-timer"]
    }
}
struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }

func makeSources(_ options: Options) throws -> [CVPixelBuffer] {
    var sources: [CVPixelBuffer] = []
    for frame in 0..<options.poolSize {
        var created: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, options.width, options.height,
                                        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &created)
        guard status == kCVReturnSuccess, let buffer = created else { throw Failure("Allocate NV12 buffer: \(status)") }
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { throw Failure("Lock NV12 buffer") }
        guard let lumaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0), let chromaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else {
            CVPixelBufferUnlockBaseAddress(buffer, []); throw Failure("NV12 source has no planes")
        }
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        memset(lumaBase, 16, lumaStride * options.height)
        memset(chromaBase, 128, chromaStride * options.height / 2)
        let bytes = lumaBase.assumingMemoryBound(to: UInt8.self)
        for y in 0..<options.height {
            for x in 0..<options.width {
                let shifted = (x + frame * 11) % options.width
                bytes[y * lumaStride + x] = shifted < options.width / 4 ? 220 : (((x / 32 + y / 32) & 1) == 0 ? 48 : 96)
            }
        }
        // Content-state marker. Source buffers are NEVER mutated after creation,
        // even when the same immutable state is submitted concurrently again.
        for bit in 0..<16 {
            let luma: UInt8 = (frame & (1 << bit)) != 0 ? 235 : 16
            let x0 = 8 + bit * 3
            for y in 8..<16 { for x in x0..<(x0 + 3) { bytes[y * lumaStride + x] = luma } }
        }
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        sources.append(buffer)
    }
    return sources
}

// A diagnostic read of the inspected reference's private CF session lets us
// verify actual hardware selection without changing its source. Fail explicitly
// if a future reference revision changes this field or its representation.
func referenceSession(_ encoder: VideoEncoder) throws -> VTCompressionSession {
    guard let field = Mirror(reflecting: encoder).children.first(where: { $0.label == "compressionSession" }),
          let unwrapped = Mirror(reflecting: field.value).children.first?.value else {
        throw Failure("The unmodified reference did not expose an initialized compressionSession to diagnostics")
    }
    let raw = unwrapped as CFTypeRef
    guard CFGetTypeID(raw) == VTCompressionSessionGetTypeID() else { throw Failure("Reference compressionSession type changed") }
    return unsafeBitCast(raw, to: VTCompressionSession.self)
}
func property(_ session: VTCompressionSession, _ key: CFString) -> [String: Any] {
    var result: Unmanaged<CFTypeRef>?
    let status = VTSessionCopyProperty(session, key: key, allocator: kCFAllocatorDefault, valueOut: &result)
    return ["status": status, "value": result?.takeRetainedValue() ?? NSNull()]
}

final class Submission {
    let sequence: UInt64
    let contentState: Int
    let before: UInt64
    var after = UInt64.max
    init(sequence: UInt64, contentState: Int, before: UInt64) {
        self.sequence = sequence; self.contentState = contentState; self.before = before
    }
}
final class Counters {
    var ticks = 0
    var submitted = 0
    var skippedAtBound = 0
    var encoded = 0
    var bytes = 0
    var keyframes = 0
    var maxOutstanding = 0
    var unmatchedCallbacks = 0
    var sequenceIDs: Set<UInt64> = []
    var contentStates: Set<Int> = []
    var latencyMs: [Double] = []
    var submitTimes: [Double] = []
    var encodeTimes: [Double] = []
    func json(seconds: Double) -> [String: Any] {
        let latency = latencyMs.sorted()
        return ["seconds": seconds, "timerTicks": ticks, "submitted": submitted, "submittedFPS": Double(submitted) / seconds,
                "skippedAtBound": skippedAtBound, "encoded": encoded, "encodedFPS": Double(encoded) / seconds,
                "distinctEncodedSequenceIDs": sequenceIDs.count, "distinctImmutableContentStates": contentStates.count,
                "keyframes": keyframes, "bitrateMbps": Double(bytes) * 8 / seconds / 1_000_000,
                "maximumOutstanding": maxOutstanding, "unmatchedCallbacks": unmatchedCallbacks,
                "meanEncodeMs": latency.isEmpty ? 0 : latency.reduce(0, +) / Double(latency.count),
                "p95EncodeMs": latency.isEmpty ? 0 : latency[min(latency.count - 1, Int(Double(latency.count) * 0.95))],
                "maxEncodeMs": latency.last ?? 0]
    }
}

final class ThroughputProbe {
    let options: Options
    let sources: [CVPixelBuffer]
    let lock = NSLock()
    let queue = DispatchQueue(label: "reference.encoder-throughput", qos: .userInteractive)
    let all = Counters()
    let steady = Counters()
    var epochs: [Int: Counters] = [:]
    var pending: [Submission] = []
    var encoder: VideoEncoder?
    var sequence: UInt64 = 0
    var begun = UInt64(0)
    var timer: DispatchSourceTimer?
    var output: FileHandle?
    var introspection: [String: Any] = [:]
    init(_ options: Options, _ sources: [CVPixelBuffer]) { self.options = options; self.sources = sources }

    func start() throws {
        if let destination = options.outputPath {
            FileManager.default.createFile(atPath: destination, contents: nil)
            output = try FileHandle(forWritingTo: URL(fileURLWithPath: destination))
        }
        encoder = VideoEncoder(width: options.width, height: options.height, codec: .hevc,
                               bitrateMbps: 60, quality: "ultralow", gamingBoost: false, frameRate: options.fps)
        let session = try referenceSession(encoder!)
        let hardware = property(session, kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder)
        guard (hardware["value"] as? NSNumber)?.boolValue == true else { throw Failure("Reference did not select a hardware encoder: \(hardware)") }
        introspection = ["hardware": hardware, "quality": property(session, kVTCompressionPropertyKey_Quality),
                         "profile": property(session, kVTCompressionPropertyKey_ProfileLevel),
                         "bitrate": property(session, kVTCompressionPropertyKey_AverageBitRate),
                         "expectedFPS": property(session, kVTCompressionPropertyKey_ExpectedFrameRate)]
        encoder?.onEncodedFrame = { [self] data, timestamp, keyframe in onEncoded(data, timestamp, keyframe) }
        begun = DispatchTime.now().uptimeNanoseconds + 100_000_000
        let source = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        source.schedule(deadline: DispatchTime(uptimeNanoseconds: begun), repeating: .nanoseconds(Int(1_000_000_000 / options.fps)), leeway: .nanoseconds(0))
        source.setEventHandler { [self] in submit() }
        timer = source
        emit(["stage": "ready", "configuration": options.json, "encoder": introspection,
              "sourcePool": ["immutable": true, "states": sources.count, "contentPeriodFrames": sources.count],
              "limits": "Synthetic immutable NV12 inputs; this does not measure screen capture, compositor, USB, or Android. Source states repeat, output sequence IDs do not."])
        source.resume()
        queue.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: begun + UInt64((options.warmup + options.duration) * 1_000_000_000))) { [self] in finish() }
    }

    func measured(_ elapsed: Double) -> Bool { elapsed >= options.warmup && elapsed < options.warmup + options.duration }
    func submit() {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = Double(now - begun) / 1_000_000_000
        guard elapsed < options.warmup + options.duration else { return }
        lock.lock()
        sequence += 1
        all.ticks += 1
        let isMeasured = measured(elapsed)
        let epochIndex = Int(floor(elapsed - options.warmup))
        let epoch: Counters? = isMeasured ? epochs[epochIndex] ?? Counters() : nil
        if let epoch { epochs[epochIndex] = epoch; epoch.ticks += 1; steady.ticks += 1 }
        let selected = [all] + (isMeasured ? [steady, epoch!] : [])
        if options.maximumOutstanding > 0 && pending.count >= options.maximumOutstanding {
            for counts in selected { counts.skippedAtBound += 1 }
            lock.unlock(); return
        }
        let state = Int(sequence % UInt64(sources.count))
        let record = Submission(sequence: sequence, contentState: state, before: DispatchTime.now().uptimeNanoseconds)
        pending.append(record)
        for counts in selected {
            counts.submitted += 1; counts.submitTimes.append(elapsed)
            counts.maxOutstanding = max(counts.maxOutstanding, pending.count)
        }
        lock.unlock()
        encoder?.encode(pixelBuffer: sources[state], presentationTimeStamp: CMTime(value: Int64(sequence), timescale: CMTimeScale(options.fps)))
        lock.lock(); record.after = DispatchTime.now().uptimeNanoseconds; lock.unlock()
    }

    func onEncoded(_ data: Data, _ timestamp: UInt64, _ keyframe: Bool) {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = Double(now - begun) / 1_000_000_000
        lock.lock()
        let recordIndex = pending.firstIndex { timestamp >= $0.before && timestamp <= $0.after }
        let record = recordIndex.map { pending.remove(at: $0) }
        let isMeasured = measured(elapsed)
        let epochIndex = Int(floor(elapsed - options.warmup))
        let epoch: Counters? = isMeasured ? epochs[epochIndex] ?? Counters() : nil
        if let epoch { epochs[epochIndex] = epoch }
        for counts in [all] + (isMeasured ? [steady, epoch!] : []) {
            counts.encoded += 1; counts.bytes += data.count; counts.keyframes += keyframe ? 1 : 0
            counts.encodeTimes.append(elapsed)
            counts.latencyMs.append(Double(now - timestamp) / 1_000_000)
            if let record { counts.sequenceIDs.insert(record.sequence); counts.contentStates.insert(record.contentState) }
            else { counts.unmatchedCallbacks += 1 }
        }
        output?.write(data)
        lock.unlock()
    }

    func finish() {
        timer?.cancel(); timer = nil
        let stopStarted = DispatchTime.now().uptimeNanoseconds
        // Flush via the public VT API while the unmodified reference object and
        // its callback refcon are still alive, then release the reference.
        if let encoder, let session = try? referenceSession(encoder) {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        }
        encoder?.onEncodedFrame = nil
        encoder = nil
        lock.lock()
        let totalSeconds = Double(DispatchTime.now().uptimeNanoseconds - begun) / 1_000_000_000
        let outstanding = pending.map { ["sequence": $0.sequence, "contentState": $0.contentState] as [String: Any] }
        let periods = epochs.keys.sorted().map { index in
            ["epoch": index, "metrics": epochs[index]!.json(seconds: min(1, options.duration - Double(index)))] as [String: Any]
        }
        emit(["stage": "result", "configuration": options.json, "encoder": introspection,
              "steady": steady.json(seconds: options.duration), "allIncludingWarmupAndDrain": all.json(seconds: totalSeconds),
              "epochs": periods, "uncompletedAfterDrain": outstanding,
              "drainMs": Double(DispatchTime.now().uptimeNanoseconds - stopStarted) / 1_000_000,
              "dropAccounting": "Bound skips are exact. Missing callbacks after explicit drain are uncompleted; the unmodified reference hides VT errors/drop flags, so their causes are not inferred."])
        output?.closeFile(); lock.unlock()
        exit(outstanding.isEmpty && steady.unmatchedCallbacks == 0 && steady.encoded > 0 ? 0 : 1)
    }
}

do {
    let options = try Options()
    let sources = try makeSources(options)
    let probe = ThroughputProbe(options, sources)
    try probe.start()
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + options.duration + options.warmup + 15) {
        emit(["stage": "error", "message": "Encoder probe exceeded bounded drain deadline"]); exit(1)
    }
    dispatchMain()
} catch let failure as Failure {
    emit(["stage": "error", "message": failure.message]); exit(1)
} catch {
    emit(["stage": "error", "message": error.localizedDescription]); exit(1)
}
