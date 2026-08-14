import AppKit

final class AreaRecordingBorderWindow: NSWindow {
    private let canvas: AreaRecordingBorderCanvas

    init(screen: NSScreen, selectionGlobal: CGRect) {
        let local = CGRect(
            x: selectionGlobal.minX - screen.frame.minX,
            y: selectionGlobal.minY - screen.frame.minY,
            width: selectionGlobal.width,
            height: selectionGlobal.height
        )
        canvas = AreaRecordingBorderCanvas(frame: NSRect(origin: .zero, size: screen.frame.size))
        canvas.selectionLocal = local

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        contentView = canvas
    }
}

final class AreaRecordingBorderCanvas: NSView {
    var selectionLocal: CGRect? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let selection = selectionLocal, selection.width > 1, selection.height > 1 else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        SelectionChrome.strokeDashedRect(selection, in: ctx)
    }
}
