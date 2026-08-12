import AppKit
import SwiftUI

enum RecorderGlyph {
    static func menuBar() -> NSImage {
        if let named = NSImage(named: "RecorderGlyph") {
            let image = named.copy() as? NSImage ?? named
            let aspect = max(image.size.width / max(image.size.height, 1), 22.0 / 16.0)
            let height: CGFloat = 16
            image.size = NSSize(width: (height * aspect).rounded(.toNearestOrAwayFromZero), height: height)
            image.isTemplate = true
            return image
        }
        return fallback(height: 16)
    }

    private static func fallback(height: CGFloat) -> NSImage {
        let width = height * (22.0 / 16.0)
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setStroke()
        NSColor.black.setFill()
        let monitor = NSBezierPath(
            roundedRect: NSRect(x: 1, y: height * 0.18, width: width * 0.68, height: height * 0.62),
            xRadius: 1.5,
            yRadius: 1.5
        )
        monitor.lineWidth = 1.2
        monitor.stroke()
        let stand = NSBezierPath(
            roundedRect: NSRect(x: width * 0.28, y: height * 0.05, width: width * 0.22, height: height * 0.1),
            xRadius: 0.5,
            yRadius: 0.5
        )
        stand.fill()
        let dot = NSBezierPath(
            ovalIn: NSRect(x: width * 0.74, y: height * 0.32, width: height * 0.36, height: height * 0.36)
        )
        dot.fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
