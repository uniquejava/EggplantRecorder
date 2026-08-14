import AppKit

final class WindowPickPanel: NSPanel {
    let screenFrame: CGRect
    private let canvas: WindowPickCanvas

    init(screen: NSScreen) {
        screenFrame = screen.frame
        let size = screen.frame.size
        canvas = WindowPickCanvas(frame: NSRect(origin: .zero, size: size))
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false
        contentView = canvas
        setFrame(screen.frame, display: true)
    }

    func setHighlight(_ globalRect: CGRect?) {
        guard let globalRect else {
            canvas.highlightLocal = nil
            return
        }
        let local = CGRect(
            x: globalRect.minX - screenFrame.minX,
            y: globalRect.minY - screenFrame.minY,
            width: globalRect.width,
            height: globalRect.height
        )
        canvas.highlightLocal = local.intersection(canvas.bounds)
        if canvas.highlightLocal?.isNull == true || canvas.highlightLocal?.isEmpty == true {
            canvas.highlightLocal = nil
        }
    }

    override var canBecomeKey: Bool { true }
}

final class WindowPickCanvas: NSView {
    var highlightLocal: CGRect? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if let selection = highlightLocal, selection.width > 1, selection.height > 1 {
            let dim = NSBezierPath(rect: bounds)
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.35).setFill()
            dim.fill()

            if let ctx = NSGraphicsContext.current?.cgContext {
                SelectionChrome.strokeDashedRect(selection, in: ctx)
            }

            let label = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let size = label.size(withAttributes: attrs)
            var origin = CGPoint(
                x: selection.midX - size.width / 2,
                y: selection.maxY + 8
            )
            if origin.y + size.height + 4 > bounds.maxY {
                origin.y = selection.minY - size.height - 8
            }
            let chip = CGRect(x: origin.x - 6, y: origin.y - 3, width: size.width + 12, height: size.height + 6)
            NSColor.black.withAlphaComponent(0.72).setFill()
            NSBezierPath(roundedRect: chip, xRadius: 4, yRadius: 4).fill()
            label.draw(at: origin, withAttributes: attrs)
        } else {
            NSColor.black.withAlphaComponent(0.28).setFill()
            bounds.fill()
        }
    }
}
