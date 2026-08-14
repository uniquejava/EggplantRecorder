import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

/// ScreenCaptureKit recorder: dual audio tracks, pause compresses timeline (no freeze frames).
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
        let filterAndSize = try CaptureFilter.make(
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
            let input = CaptureAudio.makeAACInput()
            if writer.canAdd(input) {
                writer.add(input)
                systemAudioInput = input
            }
        }
        if microphone {
            let input = CaptureAudio.makeAACInput()
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

        let relative = CaptureTiming.relativePTS(
            host: pts,
            sessionAnchor: sessionAnchor,
            pausedAccumulated: pausedAccumulated
        )

        switch type {
        case .screen:
            guard let videoInput, videoInput.isReadyForMoreMediaData else { return }
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let videoPTS = CaptureTiming.monotonicPTS(relative, previous: lastVideoPTS)
            if adaptor?.append(imageBuffer, withPresentationTime: videoPTS) == true {
                lastVideoPTS = videoPTS
            }
        case .audio:
            var last = lastSysAudioPTS
            _ = CaptureAudio.append(sampleBuffer, to: systemAudioInput, pts: relative, lastPTS: &last)
            lastSysAudioPTS = last
        case .microphone:
            var last = lastMicPTS
            _ = CaptureAudio.append(sampleBuffer, to: micAudioInput, pts: relative, lastPTS: &last)
            lastMicPTS = last
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lastError = error
    }

    private static func friendlyStartError(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.code == -3820 {
            return CaptureError.microphoneStartFailed
        }
        return error
    }
}
