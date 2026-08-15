import Foundation

enum CaptureError: LocalizedError, Equatable {
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
