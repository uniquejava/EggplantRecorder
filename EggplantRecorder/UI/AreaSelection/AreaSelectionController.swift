import AppKit
import CoreGraphics

struct AreaSelectionResult {
    let displayID: CGDirectDisplayID
    /// Points in the display’s logical coordinate system (top-left origin) for `SCStreamConfiguration.sourceRect`.
    let sourceRect: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
}

/// Full-screen dim overlays. Confirm toolbar is embedded **inside** the active overlay
/// (sibling above the canvas) so the mask can never steal its clicks.
@MainActor
final class AreaSelectionController {
    private var overlayWindows: [AreaOverlayWindow] = []
    private var activeScreenID: CGDirectDisplayID?
    private var onComplete: ((AreaSelectionResult) -> Void)?
    private var onCancel: (() -> Void)?
    private var escapeMonitor: Any?

    var isVisible: Bool { !overlayWindows.isEmpty }

    func show(onComplete: @escaping (AreaSelectionResult) -> Void, onCancel: @escaping () -> Void) {
        hide()
        self.onComplete = onComplete
        self.onCancel = onCancel

        for screen in NSScreen.screens {
            let window = AreaOverlayWindow(
                screen: screen,
                onCancel: { [weak self] in self?.cancel() },
                onContinue: { [weak self] in self?.confirm() }
            )
            window.selectionDelegate = self
            window.orderFrontRegardless()
            overlayWindows.append(window)
            if screen == NSScreen.main {
                activeScreenID = screen.displayID
                window.activateDefaultSelection()
            }
        }

        refreshToolbarPlacement()
        overlayWindows.first(where: { $0.screen?.displayID == activeScreenID })?
            .makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.cancel()
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 { // Return / keypad Enter
                self?.confirm()
                return nil
            }
            return event
        }
    }

    func hide() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        activeScreenID = nil
    }

    private func confirm() {
        guard let result = currentResult() else {
            NSSound.beep()
            return
        }
        let complete = onComplete
        hide()
        complete?(result)
    }

    private func cancel() {
        let cancel = onCancel
        hide()
        cancel?()
    }

    private func currentResult() -> AreaSelectionResult? {
        let window = overlayWindows.first(where: { $0.screen?.displayID == activeScreenID })
            ?? overlayWindows.first
        return window?.makeResult()
    }

    private func refreshToolbarPlacement() {
        for window in overlayWindows {
            let active = window.screen?.displayID == activeScreenID
            window.setToolbarVisible(active)
        }
    }
}

extension AreaSelectionController: AreaOverlaySelectionDelegate {
    func areaOverlayDidBeginEditing(_ window: AreaOverlayWindow) {
        activeScreenID = window.screen?.displayID
        for other in overlayWindows where other !== window {
            other.clearSelection()
        }
        refreshToolbarPlacement()
    }

    func areaOverlayDidChangeSelection(_ window: AreaOverlayWindow) {
        activeScreenID = window.screen?.displayID
        refreshToolbarPlacement()
    }
}

// MARK: - Overlay window

protocol AreaOverlaySelectionDelegate: AnyObject {
    func areaOverlayDidBeginEditing(_ window: AreaOverlayWindow)
    func areaOverlayDidChangeSelection(_ window: AreaOverlayWindow)
}

final class AreaOverlayWindow: NSWindow {
    weak var selectionDelegate: AreaOverlaySelectionDelegate?
    private let canvas: AreaSelectionCanvas
    private let confirmBar: AreaConfirmBarNSView
    private let root = NSView()

    static let toolbarHeight: CGFloat = 64
    static let toolbarWidth: CGFloat = 440
    static let toolbarBottomInset: CGFloat = 28

    init(
        screen: NSScreen,
        onCancel: @escaping () -> Void,
        onContinue: @escaping () -> Void
    ) {
        let size = screen.frame.size
        canvas = AreaSelectionCanvas(frame: NSRect(origin: .zero, size: size))
        canvas.toolbarReserveHeight = Self.toolbarHeight + Self.toolbarBottomInset + 12
        confirmBar = AreaConfirmBarNSView(frame: .zero)
        confirmBar.onCancel = onCancel
        confirmBar.onContinue = onContinue

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
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false

        root.frame = NSRect(origin: .zero, size: size)
        root.wantsLayer = true
        contentView = root

        canvas.autoresizingMask = [.width, .height]
        root.addSubview(canvas)

        confirmBar.translatesAutoresizingMaskIntoConstraints = true
        root.addSubview(confirmBar)
        // Added after canvas → always hit-tested first within its frame.
        layoutConfirmBar()
        confirmBar.isHidden = true

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

    func setToolbarVisible(_ visible: Bool) {
        confirmBar.isHidden = !visible
        if visible {
            layoutConfirmBar()
            root.addSubview(confirmBar, positioned: .above, relativeTo: canvas)
        }
    }

    private func layoutConfirmBar() {
        let width = Self.toolbarWidth
        let height = Self.toolbarHeight
        let x = (root.bounds.width - width) / 2
        let y = Self.toolbarBottomInset
        confirmBar.frame = NSRect(x: x, y: y, width: width, height: height)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        root.frame = NSRect(origin: .zero, size: frameRect.size)
        canvas.frame = root.bounds
        layoutConfirmBar()
    }

    func activateDefaultSelection() {
        canvas.installDefaultSelection()
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

// MARK: - AppKit confirm bar (reliable hit-testing)

final class AreaConfirmBarNSView: NSView {
    var onCancel: (() -> Void)?
    var onContinue: (() -> Void)?

    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let continueButton = NSButton(title: "Continue", target: nil, action: nil)
    private let hint = NSTextField(labelWithString: "Drag to select · handles to resize")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 0.96).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor

        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.isEditable = false
        hint.isBordered = false
        hint.drawsBackground = false
        hint.lineBreakMode = .byTruncatingTail

        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)

        continueButton.bezelStyle = .rounded
        continueButton.setButtonType(.momentaryPushIn)
        continueButton.isBordered = false
        continueButton.wantsLayer = true
        continueButton.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        continueButton.layer?.cornerRadius = 14
        continueButton.attributedTitle = NSAttributedString(
            string: "Continue",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ]
        )
        continueButton.target = self
        continueButton.action = #selector(continueClicked)

        addSubview(hint)
        addSubview(cancelButton)
        addSubview(continueButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 14
        let btnH: CGFloat = 28
        let contW: CGFloat = 96
        let cancelW: CGFloat = 72
        continueButton.frame = NSRect(
            x: bounds.width - pad - contW,
            y: (bounds.height - btnH) / 2,
            width: contW,
            height: btnH
        )
        cancelButton.frame = NSRect(
            x: continueButton.frame.minX - 10 - cancelW,
            y: (bounds.height - btnH) / 2,
            width: cancelW,
            height: btnH
        )
        hint.frame = NSRect(
            x: pad,
            y: (bounds.height - 18) / 2,
            width: max(40, cancelButton.frame.minX - pad - 12),
            height: 18
        )
    }

    /// Opaque to hit-testing across the whole bar (no fall-through to dim canvas).
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }

    @objc private func cancelClicked() { onCancel?() }
    @objc private func continueClicked() { onContinue?() }
}

// MARK: - Canvas

private enum HandlePosition: CaseIterable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
}

final class AreaSelectionCanvas: NSView {
    var onBeginEditing: (() -> Void)?
    var onSelectionChanged: (() -> Void)?
    /// Keep selection / handles above the embedded toolbar.
    var toolbarReserveHeight: CGFloat = 0

    private(set) var selectionInWindowCoords: CGRect?
    private var dragKind: DragKind = .none
    private var dragStart: CGPoint = .zero
    private var selectionAtDragStart: CGRect = .zero
    private let handleSize: CGFloat = 11
    private let minSize: CGFloat = 40

    /// Soft sky blue matching OMI-style area chrome (~#A3C1F0).
    private static let selectionBlue = NSColor(srgbRed: 163 / 255, green: 193 / 255, blue: 240 / 255, alpha: 1)

    private enum DragKind {
        case none
        case creating
        case moving
        case resizing(HandlePosition)
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    private var usableBounds: CGRect {
        bounds.divided(atDistance: toolbarReserveHeight, from: .minYEdge).remainder
    }

    func installDefaultSelection() {
        let area = usableBounds
        let insetX = area.width * 0.18
        let insetY = area.height * 0.18
        selectionInWindowCoords = area.insetBy(dx: insetX, dy: insetY)
        needsDisplay = true
        onSelectionChanged?()
    }

    func clearSelection() {
        selectionInWindowCoords = nil
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let the toolbar sibling own the bottom strip.
        if point.y < toolbarReserveHeight {
            return nil
        }
        return super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        if let selection = selectionInWindowCoords {
            let dim = NSBezierPath(rect: bounds)
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.45).setFill()
            dim.fill()

            // Light-blue dashed border via CGContext (reliable dash + color).
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.setStrokeColor(Self.selectionBlue.cgColor)
                ctx.setLineWidth(2)
                ctx.setLineDash(phase: 0, lengths: [6, 5])
                ctx.stroke(selection.insetBy(dx: 1, dy: 1))
                ctx.restoreGState()
            }

            // Handles: blue fill + white ring (corners + mid-edges).
            for handle in HandlePosition.allCases {
                let rect = handleRect(handle, in: selection)
                Self.selectionBlue.setFill()
                NSBezierPath(ovalIn: rect).fill()
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
                ring.lineWidth = 1.5
                NSColor.white.setStroke()
                ring.stroke()
            }

            let label = "\(Int(selection.width)) × \(Int(selection.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let size = label.size(withAttributes: attrs)
            let labelOrigin = CGPoint(
                x: selection.midX - size.width / 2,
                y: min(selection.maxY + 8, bounds.maxY - size.height - 4)
            )
            let chip = CGRect(
                x: labelOrigin.x - 6,
                y: labelOrigin.y - 3,
                width: size.width + 12,
                height: size.height + 6
            )
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: chip, xRadius: 4, yRadius: 4).fill()
            label.draw(at: labelOrigin, withAttributes: attrs)
        } else {
            NSColor.black.withAlphaComponent(0.45).setFill()
            bounds.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onBeginEditing?()

        if let selection = selectionInWindowCoords {
            if let handle = hitHandle(at: point, in: selection) {
                dragKind = .resizing(handle)
                dragStart = point
                selectionAtDragStart = selection
                return
            }
            if selection.contains(point) {
                dragKind = .moving
                dragStart = point
                selectionAtDragStart = selection
                return
            }
        }

        dragKind = .creating
        dragStart = point
        selectionInWindowCoords = CGRect(origin: point, size: .zero)
        selectionAtDragStart = selectionInWindowCoords!
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch dragKind {
        case .none:
            break
        case .creating:
            let rect = CGRect(
                x: min(dragStart.x, point.x),
                y: min(dragStart.y, point.y),
                width: abs(point.x - dragStart.x),
                height: abs(point.y - dragStart.y)
            )
            selectionInWindowCoords = clamp(rect)
            needsDisplay = true
            onSelectionChanged?()
        case .moving:
            var rect = selectionAtDragStart
            rect.origin.x += point.x - dragStart.x
            rect.origin.y += point.y - dragStart.y
            selectionInWindowCoords = clamp(rect)
            needsDisplay = true
            onSelectionChanged?()
        case .resizing(let handle):
            let dx = point.x - dragStart.x
            let dy = point.y - dragStart.y
            selectionInWindowCoords = clamp(resizedByDelta(selectionAtDragStart, handle: handle, dx: dx, dy: dy))
            needsDisplay = true
            onSelectionChanged?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let selection = selectionInWindowCoords, selection.width < minSize || selection.height < minSize {
            var r = selection
            let area = usableBounds
            if r.width < minSize {
                r.size.width = minSize
                r.origin.x = min(max(area.minX, r.midX - minSize / 2), area.maxX - minSize)
            }
            if r.height < minSize {
                r.size.height = minSize
                r.origin.y = min(max(area.minY, r.midY - minSize / 2), area.maxY - minSize)
            }
            selectionInWindowCoords = clamp(r)
            needsDisplay = true
            onSelectionChanged?()
        }
        dragKind = .none
    }

    private func clamp(_ rect: CGRect) -> CGRect {
        let area = usableBounds
        var r = rect
        r.size.width = max(minSize, min(r.width, area.width))
        r.size.height = max(minSize, min(r.height, area.height))
        if r.minX < area.minX { r.origin.x = area.minX }
        if r.minY < area.minY { r.origin.y = area.minY }
        if r.maxX > area.maxX { r.origin.x = area.maxX - r.width }
        if r.maxY > area.maxY { r.origin.y = area.maxY - r.height }
        return r
    }

    /// Move the grabbed edge(s) by drag delta from mouseDown — zero movement keeps the rect unchanged.
    /// (Absolute “edge = mouse” math collapses height/width to ~0 on the first drag tick because
    /// the handle sits on that edge, then `clamp` snaps it to `minSize`.)
    private func resizedByDelta(_ start: CGRect, handle: HandlePosition, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = start.minX
        var maxX = start.maxX
        var minY = start.minY
        var maxY = start.maxY

        switch handle {
        case .topLeft:
            minX += dx
            maxY += dy
        case .top:
            maxY += dy
        case .topRight:
            maxX += dx
            maxY += dy
        case .left:
            minX += dx
        case .right:
            maxX += dx
        case .bottomLeft:
            minX += dx
            minY += dy
        case .bottom:
            minY += dy
        case .bottomRight:
            maxX += dx
            minY += dy
        }

        return CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
    }

    private func handleRect(_ handle: HandlePosition, in selection: CGRect) -> CGRect {
        let p = handlePoint(handle, in: selection)
        return CGRect(
            x: p.x - handleSize / 2,
            y: p.y - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
    }

    private func handlePoint(_ handle: HandlePosition, in selection: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: selection.minX, y: selection.maxY)
        case .top: return CGPoint(x: selection.midX, y: selection.maxY)
        case .topRight: return CGPoint(x: selection.maxX, y: selection.maxY)
        case .left: return CGPoint(x: selection.minX, y: selection.midY)
        case .right: return CGPoint(x: selection.maxX, y: selection.midY)
        case .bottomLeft: return CGPoint(x: selection.minX, y: selection.minY)
        case .bottom: return CGPoint(x: selection.midX, y: selection.minY)
        case .bottomRight: return CGPoint(x: selection.maxX, y: selection.minY)
        }
    }

    private func hitHandle(at point: CGPoint, in selection: CGRect) -> HandlePosition? {
        for handle in HandlePosition.allCases {
            if handleRect(handle, in: selection).insetBy(dx: -4, dy: -4).contains(point) {
                return handle
            }
        }
        return nil
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }
}
