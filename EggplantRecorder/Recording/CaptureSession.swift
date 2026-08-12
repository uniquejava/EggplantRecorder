import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

/// ScreenCaptureKit recorder ported from Wails `capture_recorder.m`.
/// Dual audio tracks, pause compresses timeline (no freeze frames).
final class CaptureSession: NSObject, SCStreamDelegate, SCStreamOutput {
    private let queue = DispatchQueue(label: "click.yinsb.eggplantrecorder.capture")

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var writing = false
    private var paused = false
    private var sessionStarted = false
    private var hasHostPTS = false
    private var pauseBeganValid = false
    private var resumePending = false

    private var sessionAnchor = CMTime.invalid
    private var pausedAccumulated = CMTime.zero
    private var pauseBeganAt = CMTime.invalid
    private var lastHostPTS = CMTime.invalid
    private var lastVideoPTS = CMTime.invalid
    private var lastSysAudioPTS = CMTime.invalid
    private var lastMicPTS = CMTime.invalid

    private(set) var outputPath: String = ""
    private(set) var lastError: Error?

    var isWriting: Bool { writing }
    var isPaused: Bool { paused }

    func start(
        sourceID: String,
        kind: RecordingKind,
        outputPath: String,
        systemAudio: Bool,
        microphone: Bool,
        microphoneDeviceID: String?,
        excludePID: pid_t,
        showCursor: Bool = true,
        areaSourceRect: CGRect? = nil,
        areaPixelWidth: Int? = nil,
        areaPixelHeight: Int? = nil
    ) async throws {
        if writing {
            throw CaptureError.alreadyRecording
        }

        if microphone {
            let granted = await CapturePermissions.requestMicrophoneAccess()
            guard granted else {
                throw CaptureError.microphoneDenied
            }
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let filterAndSize = try Self.makeFilter(
            content: content,
            sourceID: sourceID,
            kind: kind,
            excludePID: excludePID,
            areaSourceRect: areaSourceRect,
            areaPixelWidth: areaPixelWidth,
            areaPixelHeight: areaPixelHeight
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.queue.async {
                do {
                    try self.beginWriting(
                        filter: filterAndSize.filter,
                        width: filterAndSize.width,
                        height: filterAndSize.height,
                        sourceRect: filterAndSize.sourceRect,
                        systemAudio: systemAudio,
                        microphone: microphone,
                        microphoneDeviceID: microphoneDeviceID,
                        showCursor: showCursor,
                        outputPath: outputPath
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.queue.async {
                do {
                    let path = try self.stopAndFinish()
                    continuation.resume(returning: path)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func pause() {
        queue.async {
            self.paused = true
            if self.hasHostPTS {
                self.pauseBeganAt = self.lastHostPTS
                self.pauseBeganValid = true
            }
        }
    }

    func resume() {
        queue.async {
            self.paused = false
            if self.pauseBeganValid {
                self.resumePending = true
            }
        }
    }

    // MARK: - Setup

    private func beginWriting(
        filter: SCContentFilter,
        width: Int,
        height: Int,
        sourceRect: CGRect?,
        systemAudio: Bool,
        microphone: Bool,
        microphoneDeviceID: String?,
        showCursor: Bool,
        outputPath: String
    ) throws {
        self.outputPath = outputPath
        writing = false
        paused = false
        sessionStarted = false
        hasHostPTS = false
        pauseBeganValid = false
        resumePending = false
        sessionAnchor = .invalid
        pausedAccumulated = .zero
        pauseBeganAt = .invalid
        lastHostPTS = .invalid
        lastVideoPTS = .invalid
        lastSysAudioPTS = .invalid
        lastMicPTS = .invalid
        lastError = nil
        systemAudioInput = nil
        micAudioInput = nil

        let url = URL(fileURLWithPath: outputPath)
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(url: url, fileType: .mp4)
        self.writer = writer

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 6,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        self.videoInput = videoInput

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: attrs
        )

        guard writer.canAdd(videoInput) else {
            throw CaptureError.cannotAddVideoInput
        }
        writer.add(videoInput)

        if systemAudio {
            let input = Self.makeAACAudioInput()
            if writer.canAdd(input) {
                writer.add(input)
                systemAudioInput = input
            }
        }
        if microphone {
            let input = Self.makeAACAudioInput()
            if writer.canAdd(input) {
                writer.add(input)
                micAudioInput = input
            }
        }

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        if let sourceRect, sourceRect.width > 0, sourceRect.height > 0 {
            config.sourceRect = sourceRect
            config.scalesToFit = false
        }
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 8
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = showCursor
        config.capturesAudio = systemAudio
        if systemAudio || microphone {
            config.sampleRate = 48_000
            config.channelCount = 2
        }
        config.captureMicrophone = microphone
        if microphone, let microphoneDeviceID, !microphoneDeviceID.isEmpty {
            config.microphoneCaptureDeviceID = microphoneDeviceID
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream

        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if systemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        if microphone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        }

        let sem = DispatchSemaphore(value: 0)
        var startError: Error?
        stream.startCapture { error in
            startError = error
            sem.signal()
        }
        sem.wait()
        if let startError {
            throw Self.friendlyStartError(startError)
        }
        writing = true
    }

    private func stopAndFinish() throws -> String {
        writing = false
        let stream = self.stream
        self.stream = nil

        let sem = DispatchSemaphore(value: 0)
        stream?.stopCapture { [weak self] error in
            if let error {
                self?.lastError = error
            }
            sem.signal()
        }
        if stream != nil {
            sem.wait()
        }

        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        micAudioInput?.markAsFinished()

        let done = DispatchSemaphore(value: 0)
        writer?.finishWriting {
            done.signal()
        }
        done.wait()

        if writer?.status == .failed {
            let err = writer?.error ?? CaptureError.finalizeFailed
            lastError = err
            throw err
        }
        return outputPath
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard writing, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        lastHostPTS = pts
        hasHostPTS = true

        if resumePending && pauseBeganValid {
            let pausedFor = CMTimeSubtract(pts, pauseBeganAt)
            if CMTimeCompare(pausedFor, .zero) > 0 {
                pausedAccumulated = CMTimeAdd(pausedAccumulated, pausedFor)
            }
            pauseBeganValid = false
            resumePending = false
        }

        if paused { return }

        if !sessionStarted {
            guard type == .screen else { return }
            guard let writer else { return }
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            sessionStarted = true
            sessionAnchor = pts
        }

        let relative = relativePTS(forHost: pts)

        switch type {
        case .screen:
            guard let videoInput, videoInput.isReadyForMoreMediaData else { return }
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let videoPTS = monotonicPTS(relative, previous: lastVideoPTS)
            if adaptor?.append(imageBuffer, withPresentationTime: videoPTS) == true {
                lastVideoPTS = videoPTS
            }
        case .audio:
            var last = lastSysAudioPTS
            _ = appendAudio(sampleBuffer, to: systemAudioInput, pts: relative, lastPTS: &last)
            lastSysAudioPTS = last
        case .microphone:
            var last = lastMicPTS
            _ = appendAudio(sampleBuffer, to: micAudioInput, pts: relative, lastPTS: &last)
            lastMicPTS = last
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lastError = error
    }

    // MARK: - Timing helpers

    private func relativePTS(forHost pts: CMTime) -> CMTime {
        var relative = CMTimeSubtract(pts, sessionAnchor)
        if CMTimeCompare(pausedAccumulated, .zero) > 0 {
            relative = CMTimeSubtract(relative, pausedAccumulated)
        }
        if CMTimeCompare(relative, .zero) < 0 {
            relative = .zero
        }
        return relative
    }

    private func monotonicPTS(_ candidate: CMTime, previous: CMTime) -> CMTime {
        guard previous.isValid else { return candidate }
        if CMTimeCompare(candidate, previous) <= 0 {
            return CMTimeAdd(previous, CMTime(value: 1, timescale: 600))
        }
        return candidate
    }

    private func appendAudio(
        _ sampleBuffer: CMSampleBuffer,
        to input: AVAssetWriterInput?,
        pts: CMTime,
        lastPTS: inout CMTime
    ) -> Bool {
        guard let input, input.isReadyForMoreMediaData else { return false }
        let outPTS = monotonicPTS(pts, previous: lastPTS)
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: outPTS,
            decodeTimeStamp: .invalid
        )
        var timed: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &timed
        )
        guard let timed else { return false }
        defer { /* CF retained by Create */ }
        let ok = input.append(timed)
        if ok {
            lastPTS = outPTS
        }
        return ok
    }

    // MARK: - Filter / audio helpers

    private struct FilterAndSize {
        let filter: SCContentFilter
        let width: Int
        let height: Int
        let sourceRect: CGRect?
    }

    private static func makeFilter(
        content: SCShareableContent,
        sourceID: String,
        kind: RecordingKind,
        excludePID: pid_t,
        areaSourceRect: CGRect?,
        areaPixelWidth: Int?,
        areaPixelHeight: Int?
    ) throws -> FilterAndSize {
        switch kind {
        case .screen, .area:
            var displayID: UInt32 = 0
            if sourceID.hasPrefix("display:") {
                displayID = UInt32(String(sourceID.dropFirst("display:".count))) ?? 0
            }
            let matched = content.displays.first { $0.displayID == displayID } ?? content.displays.first
            guard let matched else {
                throw CaptureError.displayNotFound
            }

            var excluded: [SCWindow] = []
            if excludePID > 0 {
                excluded = content.windows.filter { $0.owningApplication?.processID == excludePID }
            }
            let filter = SCContentFilter(display: matched, excludingWindows: excluded)

            if kind == .area, let areaSourceRect, let areaPixelWidth, let areaPixelHeight {
                var width = areaPixelWidth
                var height = areaPixelHeight
                width -= width % 2
                height -= height % 2
                if width < 2 { width = 2 }
                if height < 2 { height = 2 }
                return FilterAndSize(
                    filter: filter,
                    width: width,
                    height: height,
                    sourceRect: areaSourceRect
                )
            }

            var width = matched.width
            var height = matched.height
            width -= width % 2
            height -= height % 2
            return FilterAndSize(filter: filter, width: width, height: height, sourceRect: nil)

        case .window:
            var windowID: UInt32 = 0
            if sourceID.hasPrefix("window:") {
                windowID = UInt32(String(sourceID.dropFirst("window:".count))) ?? 0
            }
            guard let matched = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureError.windowNotFound
            }
            var width = Int(matched.frame.width)
            var height = Int(matched.frame.height)
            width -= width % 2
            height -= height % 2
            if width < 2 { width = 2 }
            if height < 2 { height = 2 }
            let filter = SCContentFilter(desktopIndependentWindow: matched)
            return FilterAndSize(filter: filter, width: width, height: height, sourceRect: nil)
        }
    }

    private static func makeAACAudioInput() -> AVAssetWriterInput {
        var stereo = AudioChannelLayout()
        stereo.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        let layoutData = Data(bytes: &stereo, count: MemoryLayout<AudioChannelLayout>.size)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
            AVChannelLayoutKey: layoutData,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    private static func friendlyStartError(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.code == -3820 {
            return CaptureError.microphoneStartFailed
        }
        return error
    }
}

enum CaptureError: LocalizedError {
    case alreadyRecording
    case microphoneDenied
    case microphoneStartFailed
    case cannotAddVideoInput
    case displayNotFound
    case windowNotFound
    case finalizeFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Already recording"
        case .microphoneDenied:
            return "Microphone permission denied. Enable it in System Settings → Privacy & Security → Microphone."
        case .microphoneStartFailed:
            return "Failed to start microphone capture. Pick another input device, or grant Microphone permission in System Settings."
        case .cannotAddVideoInput:
            return "Cannot add video input"
        case .displayNotFound:
            return "Display not found"
        case .windowNotFound:
            return "Window not found"
        case .finalizeFailed:
            return "Failed to finalize recording"
        }
    }
}
