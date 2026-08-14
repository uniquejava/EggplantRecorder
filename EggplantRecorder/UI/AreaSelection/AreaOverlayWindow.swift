import AppKit

@MainActor
protocol AreaOverlaySelectionDelegate: AnyObject {
    func areaOverlayDidBeginEditing(_ window: AreaOverlayWindow)
    func areaOverlayDidChangeSelection(_ window: AreaOverlayWindow)
}

final class AreaOverlayWindow: NSWindow {
    weak var selectionDelegate: AreaOverlaySelectionDelegate?
    private let canvas: AreaSelectionCanvas
    private let root = NSView()

    init(screen: NSScreen) {
        let size = screen.frame.size
        canvas = AreaSelectionCanvas(frame: NSRect(origin: .zero, size: size))

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
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        // Below OptionsBar (statusWindow + 3) so the panel receives clicks.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false

        root.frame = NSRect(origin: .zero, size: size)
        root.wantsLayer = true
        contentView = root

        canvas.autoresizingMask = [.width, .height]
        root.addSubview(canvas)

        canvas.onBeginEditing = { [weak self] in
            guard let self else { return }
            self.selectionDelegate?.areaOverlayDidBeginEditing(self)
        }
        canvas.onSelectionChanged = { [weak self] in
            guard let self else { return }
            self.selectionDelegate?.areaOverlayDidChangeSelection(self)
        }
    }

    override var canBecomeKey: Bool { true }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        root.frame = NSRect(origin: .zero, size: frameRect.size)
        canvas.frame = root.bounds
    }

    func activateDefaultSelection() {
        canvas.installDefaultSelection()
    }

    /// Restore a remembered SCK `sourceRect` (top-left, display-local). Returns false if unusable.
    @discardableResult
    func restoreSelection(sourceRect: CGRect) -> Bool {
        canvas.restoreSelection(sourceRect: sourceRect)
    }

    func clearSelection() {
        canvas.clearSelection()
    }

    func makeResult() -> AreaSelectionResult? {
        guard let screen, let rect = canvas.selectionInWindowCoords, rect.width >= 2, rect.height >= 2 else {
            return nil
        }
        let displayID = screen.displayID
        let scale = screen.backingScaleFactor

        let global = convertToScreen(rect)
        let screenFrame = screen.frame
        let localX = global.minX - screenFrame.minX
        let localY = screenFrame.maxY - global.maxY
        var source = CGRect(x: localX, y: localY, width: global.width, height: global.height)
        source = source.integral

        var pixelW = Int((source.width * scale).rounded())
        var pixelH = Int((source.height * scale).rounded())
        pixelW -= pixelW % 2
        pixelH -= pixelH % 2
        if pixelW < 2 { pixelW = 2 }
        if pixelH < 2 { pixelH = 2 }

        return AreaSelectionResult(
            displayID: displayID,
            sourceRect: source,
            pixelWidth: pixelW,
            pixelHeight: pixelH
        )
    }
}
