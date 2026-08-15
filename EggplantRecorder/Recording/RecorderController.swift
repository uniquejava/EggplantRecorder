import Foundation

@MainActor
final class RecorderController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    /// True from the moment a start/stop is requested until it resolves. `isRecording`
    /// alone can't gate re-entry: it only flips *after* the await (audit #1).
    @Published private(set) var isBusy = false

    private let session = CaptureSession()

    func start(config: RecordingConfig, outputURL: URL) async throws {
        guard !isRecording, !isBusy else {
            // Throw rather than return: a silent return let the caller flip its own state to
            // "recording" while nothing was captured.
            throw CaptureError.alreadyRecording
        }
        isBusy = true
        defer { isBusy = false }
        let excludePID = ProcessInfo.processInfo.processIdentifier
        try await session.start(
            sourceID: config.sourceID,
            kind: config.kind,
            outputPath: outputURL.path,
            systemAudio: config.systemAudio,
            microphone: config.microphone,
            microphoneDeviceID: config.microphoneDeviceID,
            excludePID: excludePID,
            showCursor: config.showCursor,
            frameRate: config.frameRate,
            resolution: config.resolution,
            areaSourceRect: config.areaSourceRect,
            areaPixelWidth: config.areaPixelWidth,
            areaPixelHeight: config.areaPixelHeight
        )
        isRecording = true
        isPaused = false
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        session.pause()
        isPaused = true
    }

    func resume() {
        guard isRecording, isPaused else { return }
        session.resume()
        isPaused = false
    }

    @discardableResult
    func stop() async throws -> String {
        guard isRecording, !isBusy else {
            throw CaptureError.finalizeFailed
        }
        isBusy = true
        // The take is over either way: if finalizing throws, `isRecording` must still clear
        // or every later start is rejected as "already recording" until relaunch.
        defer {
            isRecording = false
            isPaused = false
            isBusy = false
        }
        return try await session.stop()
    }
}
