import CoreGraphics
import Foundation

enum CaptureFrameRate: Int, CaseIterable, Identifiable, Sendable {
    case fps15 = 15
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }

    var label: String { "\(rawValue)FPS" }
}

enum CaptureResolution: String, CaseIterable, Identifiable, Sendable {
    case native
    case p1080
    case p720

    var id: String { rawValue }

    var label: String {
        switch self {
        case .native: L10n.tr("capture.native")
        case .p1080: "1080p"
        case .p720: "720p"
        }
    }

    var maxHeight: Int? {
        switch self {
        case .native: nil
        case .p1080: 1080
        case .p720: 720
        }
    }

    func outputSize(width: Int, height: Int) -> (Int, Int) {
        guard let maxH = maxHeight, height > maxH, height > 0 else {
            return even(width, height)
        }
        let scale = Double(maxH) / Double(height)
        let outWidth = Int((Double(width) * scale).rounded())
        return even(outWidth, maxH)
    }

    static func available(sourceHeight: Int) -> [CaptureResolution] {
        allCases.filter { pick in
            guard let maxH = pick.maxHeight else { return true }
            return sourceHeight > maxH
        }
    }

    private func even(_ width: Int, _ height: Int) -> (Int, Int) {
        var w = max(width, 2)
        var h = max(height, 2)
        if w % 2 != 0 { w -= 1 }
        if h % 2 != 0 { h -= 1 }
        return (max(w, 2), max(h, 2))
    }
}

enum CaptureCountdown: Int, CaseIterable, Identifiable, Sendable {
    case none = 0
    case three = 3
    case five = 5
    case ten = 10

    var id: Int { rawValue }

    var label: String {
        self == .none ? L10n.tr("countdown.none") : "\(rawValue)s"
    }
}

struct RecordingConfig {
    var kind: RecordingKind
    var sourceID: String
    var systemAudio: Bool
    var microphone: Bool
    var microphoneDeviceID: String?
    var showCursor: Bool = true
    var frameRate: CaptureFrameRate = .fps30
    var resolution: CaptureResolution = .native
    var countdown: CaptureCountdown = .none
    var areaSourceRect: CGRect?
    var areaPixelWidth: Int?
    var areaPixelHeight: Int?
}
