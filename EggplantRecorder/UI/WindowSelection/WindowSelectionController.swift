import AppKit

struct WindowSelectionResult {
    let hit: WindowHit
}

/// Hover windows with a blue dashed border; click to confirm (EggplantShot-style pick).
@MainActor
final class WindowSelectionController {
    private var panels: [WindowPickPanel] = []
    private var eventMonitors: [Any] = []
    private var hitTester = WindowHitTester.snapshot()
    private var hovered: WindowHit?
    private var onComplete: ((WindowSelectionResult) -> Void)?
    private var onCancel: (() -> Void)?
    private(set) var isActive = false

    func show(
        onComplete: @escaping (WindowSelectionResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        hide()
        self.onComplete = onComplete
        self.onCancel = onCancel
        isActive = true
        hitTester = WindowHitTester.snapshot()
        for screen in NSScreen.screens {
            let panel = WindowPickPanel(screen: screen)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        let mouse = NSEvent.mouseLocation
        if let panel = panels.first(where: { NSMouseInRect(mouse, $0.screenFrame, false) }) ?? panels.first {
            panel.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        installMonitors()
        updateHover(at: mouse)
    }

    func hide() {
        removeMonitors()
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        hovered = nil
        isActive = false
        NSCursor.arrow.set()
    }

    private func installMonitors() {
        removeMonitors()
        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .mouseMoved, .leftMouseDragged]
        if let mon = NSEvent.addLocalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            self?.handleMouse(event)
            return nil
        }) {
            eventMonitors.append(mon)
        }
        if let mon = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            self?.handleMouse(event)
        }) {
            eventMonitors.append(mon)
        }
        if let mon = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc
                self.cancel()
                return nil
            }
            return event
        }) {
            eventMonitors.append(mon)
        }
    }

    private func removeMonitors() {
        for mon in eventMonitors {
            NSEvent.removeMonitor(mon)
        }
        eventMonitors.removeAll()
    }

    private func handleMouse(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        switch event.type {
        case .mouseMoved, .leftMouseDragged:
            updateHover(at: point)
        case .leftMouseDown:
            confirmIfPossible(at: point)
        default:
            break
        }
    }

    private func updateHover(at point: CGPoint) {
        let hit = hitTester.hit(at: point)
        hovered = hit
        for panel in panels {
            panel.setHighlight(hit?.frame)
        }
        if hit != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func confirmIfPossible(at point: CGPoint) {
        guard let hit = hovered ?? hitTester.hit(at: point), hit.frame.contains(point) else {
            return
        }
        let result = WindowSelectionResult(hit: hit)
        let complete = onComplete
        hide()
        complete?(result)
    }

    private func cancel() {
        let cancel = onCancel
        hide()
        cancel?()
    }
}

// MARK: - Overlay panel

private final class WindowPickPanel: NSPanel {
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

private final class WindowPickCanvas: NSView {
    /// Soft sky blue matching Area selection chrome.
    private static let selectionBlue = NSColor(srgbRed: 163 / 255, green: 193 / 255, blue: 240 / 255, alpha: 1)

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
                ctx.saveGState()
                ctx.setStrokeColor(Self.selectionBlue.cgColor)
                ctx.setLineWidth(2)
                ctx.setLineDash(phase: 0, lengths: [6, 5])
                ctx.stroke(selection.insetBy(dx: 1, dy: 1))
                ctx.restoreGState()
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
