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
            return L10n.tr("error.alreadyRecording")
        case .microphoneDenied:
            return L10n.tr("error.microphoneDenied")
        case .microphoneStartFailed:
            return L10n.tr("error.microphoneStartFailed")
        case .cannotAddVideoInput:
            return L10n.tr("error.cannotAddVideoInput")
        case .displayNotFound:
            return L10n.tr("error.displayNotFound")
        case .windowNotFound:
            return L10n.tr("error.windowNotFound")
        case .finalizeFailed:
            return L10n.tr("error.finalizeFailed")
        }
    }
}
