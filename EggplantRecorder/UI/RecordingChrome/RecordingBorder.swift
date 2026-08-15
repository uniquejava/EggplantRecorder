import AppKit

/// Screen-sized click-through window that strokes the dashed capture frame.
/// `reframe` lets it follow a recorded window across moves, resizes, and displays.
final class RecordingBorderWindow: NSWindow {
    private let canvas = RecordingBorderCanvas()

    init(screen: NSScreen, framedGlobal: CGRect) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        contentView = canvas
        reframe(framedGlobal: framedGlobal, on: screen)
    }

    func reframe(framedGlobal: CGRect, on screen: NSScreen) {
        if frame != screen.frame {
            setFrame(screen.frame, display: true)
        }
        canvas.framedLocal = CGRect(
            x: framedGlobal.minX - screen.frame.minX,
            y: framedGlobal.minY - screen.frame.minY,
            width: framedGlobal.width,
            height: framedGlobal.height
        )
    }
}

final class RecordingBorderCanvas: NSView {
    var framedLocal: CGRect? {
        didSet {
            guard framedLocal != oldValue else { return }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let framed = framedLocal, framed.width > 1, framed.height > 1 else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        SelectionChrome.strokeDashedRect(framed, in: ctx)
    }
}
