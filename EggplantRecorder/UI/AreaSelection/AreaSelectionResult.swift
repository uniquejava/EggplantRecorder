import CoreGraphics
import Foundation

struct AreaSelectionResult {
    let displayID: CGDirectDisplayID
    /// Points in the display’s logical coordinate system (top-left origin) for `SCStreamConfiguration.sourceRect`.
    let sourceRect: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
}

/// Remembers the last area rect across launches (UserDefaults).
enum AreaSelectionMemory {
    private static let key = "click.yinsb.eggplantrecorder.lastAreaSelection"

    private struct Stored: Codable {
        var displayID: UInt32
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    static func save(_ result: AreaSelectionResult) {
        let stored = Stored(
            displayID: result.displayID,
            x: result.sourceRect.origin.x,
            y: result.sourceRect.origin.y,
            width: result.sourceRect.size.width,
            height: result.sourceRect.size.height
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> (displayID: CGDirectDisplayID, sourceRect: CGRect)? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.width >= 40, stored.height >= 40
        else { return nil }
        return (
            CGDirectDisplayID(stored.displayID),
            CGRect(x: stored.x, y: stored.y, width: stored.width, height: stored.height)
        )
    }
}
