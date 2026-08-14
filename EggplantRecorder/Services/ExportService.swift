import AVFoundation
import CoreMedia
import Foundation

enum ExportError: LocalizedError {
    case noVideo
    case cannotAddInput
    case readerFailed
    case writerFailed(String)
    case cancelled
    case rangeTooShort

    var errorDescription: String? {
        switch self {
        case .noVideo:
            return "This recording has no video track."
        case .cannotAddInput:
            return "Could not prepare the export."
        case .readerFailed:
            return "Could not read the recording."
        case .writerFailed(let message):
            return message
        case .cancelled:
            return "Export cancelled."
        case .rangeTooShort:
            return "The trimmed range is too short to export."
        }
    }
}

/// Trims a library MP4. Video is re-encoded (frame-accurate); each audio track
/// is copied so system + mic stay separate.
enum ExportService {
    private static let minDuration: TimeInterval = 0.1

    static func exportTrimmed(
        source: URL,
        start: TimeInterval,
        end: TimeInterval,
        destination: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let cancel = CancelFlag()
        try await withTaskCancellationHandler {
            try await export(
                source: source,
                start: start,
                end: end,
                destination: destination,
                progress: progress,
                cancel: cancel
            )
        } onCancel: {
            cancel.cancel()
        }
    }

    private static func export(
        source: URL,
        start: TimeInterval,
        end: TimeInterval,
        destination: URL,
        progress: (@Sendable (Double) -> Void)?,
        cancel: CancelFlag
    ) async throws {
        let trimmedStart = max(0, start)
        let trimmedEnd = max(trimmedStart + minDuration, end)
        guard trimmedEnd - trimmedStart >= minDuration else {
            throw ExportError.rangeTooShort
        }

        let asset = AVURLAsset(url: source)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let videoTrack = videoTracks.first else {
            throw ExportError.noVideo
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let mapped = naturalSize.applying(transform)
        var width = Int(abs(mapped.width).rounded())
        var height = Int(abs(mapped.height).rounded())
        if width % 2 != 0 { width -= 1 }
        if height % 2 != 0 { height -= 1 }
        guard width > 0, height > 0 else {
            throw ExportError.noVideo
        }

        let timescale: CMTimeScale = 600
        let startTime = CMTime(seconds: trimmedStart, preferredTimescale: timescale)
        let durationTime = CMTime(seconds: trimmedEnd - trimmedStart, preferredTimescale: timescale)
        let timeRange = CMTimeRange(start: startTime, duration: durationTime)

        var audioHints: [CMFormatDescription?] = []
        audioHints.reserveCapacity(audioTracks.count)
        for track in audioTracks {
            let descs = try await track.load(.formatDescriptions)
            audioHints.append(descs.first)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try write(
                        asset: asset,
                        videoTrack: videoTrack,
                        audioTracks: audioTracks,
                        audioHints: audioHints,
                        transform: transform,
                        width: width,
                        height: height,
                        timeRange: timeRange,
                        destination: destination,
                        progress: progress,
                        cancel: cancel
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func write(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        audioTracks: [AVAssetTrack],
        audioHints: [CMFormatDescription?],
        transform: CGAffineTransform,
        width: Int,
        height: Int,
        timeRange: CMTimeRange,
        destination: URL,
        progress: (@Sendable (Double) -> Void)?,
        cancel: CancelFlag
    ) throws {
        if cancel.isCancelled { throw ExportError.cancelled }

        try? FileManager.default.removeItem(at: destination)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange

        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw ExportError.cannotAddInput }
        reader.add(videoOutput)

        var audioOutputs: [AVAssetReaderTrackOutput] = []
        audioOutputs.reserveCapacity(audioTracks.count)
        for track in audioTracks {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw ExportError.cannotAddInput }
            reader.add(output)
            audioOutputs.append(output)
        }

        let writer = try AVAssetWriter(url: destination, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(width * height * 6, 1_000_000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform
        guard writer.canAdd(videoInput) else { throw ExportError.cannotAddInput }
        writer.add(videoInput)

        var audioInputs: [AVAssetWriterInput] = []
        audioInputs.reserveCapacity(audioTracks.count)
        for hint in audioHints {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: nil,
                sourceFormatHint: hint
            )
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw ExportError.cannotAddInput }
            writer.add(input)
            audioInputs.append(input)
        }

        guard reader.startReading() else {
            throw reader.error.map { ExportError.writerFailed($0.localizedDescription) } ?? .readerFailed
        }
        guard writer.startWriting() else {
            throw writer.error.map { ExportError.writerFailed($0.localizedDescription) } ?? .cannotAddInput
        }
        writer.startSession(atSourceTime: .zero)

        let offset = timeRange.start
        let totalSeconds = max(CMTimeGetSeconds(timeRange.duration), minDuration)
        let pumpQueue = DispatchQueue(label: "click.yinsb.eggplantrecorder.export")
        let done = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var remaining = 1 + audioInputs.count
        var pumpError: Error?

        func finishOne() {
            lock.lock()
            guard remaining > 0 else {
                lock.unlock()
                return
            }
            remaining -= 1
            let isLast = remaining == 0
            lock.unlock()
            if isLast { done.signal() }
        }

        func fail(_ error: Error) {
            lock.lock()
            if pumpError == nil { pumpError = error }
            let shouldSignal = remaining > 0
            remaining = 0
            lock.unlock()
            reader.cancelReading()
            writer.cancelWriting()
            if shouldSignal { done.signal() }
        }

        pump(
            output: videoOutput,
            input: videoInput,
            offset: offset,
            queue: pumpQueue,
            cancel: cancel,
            onSample: { sample in
                let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                if totalSeconds > 0 {
                    progress?(min(0.99, max(0, seconds / totalSeconds)))
                }
            },
            onFinished: finishOne,
            onFailure: fail
        )

        for (output, input) in zip(audioOutputs, audioInputs) {
            pump(
                output: output,
                input: input,
                offset: offset,
                queue: pumpQueue,
                cancel: cancel,
                onSample: { _ in },
                onFinished: finishOne,
                onFailure: fail
            )
        }

        done.wait()

        if cancel.isCancelled {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            throw ExportError.cancelled
        }
        if let pumpError {
            try? FileManager.default.removeItem(at: destination)
            throw pumpError
        }
        if reader.status == .failed {
            try? FileManager.default.removeItem(at: destination)
            throw reader.error.map { ExportError.writerFailed($0.localizedDescription) } ?? .readerFailed
        }

        let finish = DispatchSemaphore(value: 0)
        writer.finishWriting { finish.signal() }
        finish.wait()

        if writer.status != .completed {
            try? FileManager.default.removeItem(at: destination)
            throw writer.error.map { ExportError.writerFailed($0.localizedDescription) }
                ?? .writerFailed("Export failed.")
        }
        progress?(1)
    }

    private static func pump(
        output: AVAssetReaderOutput,
        input: AVAssetWriterInput,
        offset: CMTime,
        queue: DispatchQueue,
        cancel: CancelFlag,
        onSample: @escaping (CMSampleBuffer) -> Void,
        onFinished: @escaping () -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        var finished = false
        input.requestMediaDataWhenReady(on: queue) {
            guard !finished else { return }
            while input.isReadyForMoreMediaData {
                if cancel.isCancelled {
                    finished = true
                    input.markAsFinished()
                    onFailure(ExportError.cancelled)
                    return
                }
                guard let sample = output.copyNextSampleBuffer() else {
                    finished = true
                    input.markAsFinished()
                    onFinished()
                    return
                }
                guard let shifted = shiftedSample(sample, offset: offset) else {
                    finished = true
                    input.markAsFinished()
                    onFailure(ExportError.writerFailed("Could not adjust sample timing."))
                    return
                }
                onSample(shifted)
                if !input.append(shifted) {
                    finished = true
                    input.markAsFinished()
                    onFailure(ExportError.writerFailed("Could not write media data."))
                    return
                }
            }
        }
    }

    private static func shiftedSample(_ sample: CMSampleBuffer, offset: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(
            sample,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &count
        )
        guard count > 0 else { return sample }
        var timings = Array(repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(
            sample,
            entryCount: count,
            arrayToFill: &timings,
            entriesNeededOut: &count
        )
        for i in 0..<timings.count {
            timings[i].presentationTimeStamp = CMTimeSubtract(timings[i].presentationTimeStamp, offset)
            if CMTIME_IS_VALID(timings[i].decodeTimeStamp) {
                timings[i].decodeTimeStamp = CMTimeSubtract(timings[i].decodeTimeStamp, offset)
            }
        }
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sample,
            sampleTimingEntryCount: count,
            sampleTimingArray: &timings,
            sampleBufferOut: &copy
        )
        guard status == noErr else { return nil }
        return copy
    }
}

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
