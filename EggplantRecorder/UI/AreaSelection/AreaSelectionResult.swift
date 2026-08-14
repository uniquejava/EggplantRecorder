import AppKit
import CoreGraphics
import Foundation

struct AreaSelectionResult {
    let displayID: CGDirectDisplayID
    /// Points in the display’s logical coordinate system (top-left origin) for `SCStreamConfiguration.sourceRect`.
    let sourceRect: CGRect
    let pixelWidth: Int
    let pixelHeight: Int

    /// Convert a Cocoa-global window frame into a single-display SCK area preset
    /// (largest intersecting screen, clamped to that screen).
    static func presetFromWindowFrame(_ cocoaGlobal: CGRect) -> (displayID: CGDirectDisplayID, sourceRect: CGRect)? {
        guard cocoaGlobal.width >= 40, cocoaGlobal.height >= 40 else { return nil }

        let screen = NSScreen.screens
            .map { screen -> (NSScreen, CGFloat) in
                let overlap = screen.frame.intersection(cocoaGlobal)
                let area = overlap.isNull ? 0 : overlap.width * overlap.height
                return (screen, area)
            }
            .filter { $0.1 > 0 }
            .max(by: { $0.1 < $1.1 })?
            .0
            ?? NSScreen.main
        guard let screen else { return nil }

        let clipped = cocoaGlobal.intersection(screen.frame)
        guard !clipped.isNull, clipped.width >= 40, clipped.height >= 40 else { return nil }

        let sf = screen.frame
        let source = CGRect(
            x: clipped.minX - sf.minX,
            y: sf.maxY - clipped.maxY,
            width: clipped.width,
            height: clipped.height
        ).integral
        guard source.width >= 40, source.height >= 40 else { return nil }
        return (screen.displayID, source)
    }
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
