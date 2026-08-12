import Foundation

@MainActor
final class RecorderController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false

    private let session = CaptureSession()

    func start(config: RecordingConfig, outputURL: URL) async throws {
        guard !isRecording else { return }
        let excludePID = ProcessInfo.processInfo.processIdentifier
        try await session.start(
            sourceID: config.sourceID,
            kind: config.kind,
            outputPath: outputURL.path,
            systemAudio: config.systemAudio,
            microphone: config.microphone,
            microphoneDeviceID: config.microphoneDeviceID,
            excludePID: excludePID
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
        guard isRecording else {
            throw CaptureError.finalizeFailed
        }
        let path = try await session.stop()
        isRecording = false
        isPaused = false
        return path
    }
}
