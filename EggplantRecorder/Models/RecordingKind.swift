import Foundation

enum RecordingKind: String, Hashable, Comparable {
    case screen
    case window
    case area

    static func < (lhs: RecordingKind, rhs: RecordingKind) -> Bool {
        lhs.displayName < rhs.displayName
    }

    var displayName: String {
        switch self {
        case .screen: return "Screen"
        case .window: return "Window"
        case .area: return "Area"
        }
    }

    var filePrefix: String {
        switch self {
        case .screen: return "Screen"
        case .window: return "Window"
        case .area: return "Area"
        }
    }

    static func from(filename: String) -> RecordingKind {
        let lower = filename.lowercased()
        if lower.hasPrefix("window-") { return .window }
        if lower.hasPrefix("area-") { return .area }
        return .screen
    }
}
