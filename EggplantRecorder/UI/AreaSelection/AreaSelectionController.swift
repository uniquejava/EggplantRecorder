import AppKit
import CoreGraphics

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

/// Full-screen dim overlays with a live selection. Options bar is a separate higher-level
/// `NSPanel` (same OMI glass UI as Screen / Window) — no Cancel/Continue chrome here.
@MainActor
final class AreaSelectionController {
    private var overlayWindows: [AreaOverlayWindow] = []
    private var activeScreenID: CGDirectDisplayID?
    private var onSelectionChanged: ((AreaSelectionResult?) -> Void)?
    private var onCancel: (() -> Void)?
    private var escapeMonitor: Any?

    /// Space reserved at the bottom so handles stay above the options panel (~230 + 16pt).
    static let optionsReserveHeight: CGFloat = 260

    var isVisible: Bool { !overlayWindows.isEmpty }

    func show(
        onSelectionChanged: @escaping (AreaSelectionResult?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        hide()
        self.onSelectionChanged = onSelectionChanged
        self.onCancel = onCancel

        let remembered = AreaSelectionMemory.load()

        for screen in NSScreen.screens {
            let window = AreaOverlayWindow(screen: screen)
            window.selectionDelegate = self
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }

        if let remembered,
           let match = overlayWindows.first(where: { $0.screen?.displayID == remembered.displayID }),
           match.restoreSelection(sourceRect: remembered.sourceRect)
        {
            activeScreenID = remembered.displayID
            for other in overlayWindows where other !== match {
                other.clearSelection()
            }
            match.makeKeyAndOrderFront(nil)
        } else if let main = overlayWindows.first(where: { $0.screen == NSScreen.main })
            ?? overlayWindows.first
        {
            activeScreenID = main.screen?.displayID
            main.activateDefaultSelection()
            main.makeKeyAndOrderFront(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        publishSelection()

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.cancel()
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
        onSelectionChanged = nil
        onCancel = nil
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

    private func publishSelection() {
        let result = currentResult()
        if let result {
            AreaSelectionMemory.save(result)
        }
        onSelectionChanged?(result)
    }
}

extension AreaSelectionController: AreaOverlaySelectionDelegate {
    func areaOverlayDidBeginEditing(_ window: AreaOverlayWindow) {
        activeScreenID = window.screen?.displayID
        for other in overlayWindows where other !== window {
            other.clearSelection()
        }
        publishSelection()
    }

    func areaOverlayDidChangeSelection(_ window: AreaOverlayWindow) {
        activeScreenID = window.screen?.displayID
        publishSelection()
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
    private let root = NSView()

    init(screen: NSScreen) {
        let size = screen.frame.size
        canvas = AreaSelectionCanvas(frame: NSRect(origin: .zero, size: size))
        canvas.toolbarReserveHeight = AreaSelectionController.optionsReserveHeight

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
        // Below OptionsBar (statusWindow + 3) so the glass panel receives clicks.
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

// MARK: - Canvas

private enum HandlePosition: CaseIterable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
}

final class AreaSelectionCanvas: NSView {
    var onBeginEditing: (() -> Void)?
    var onSelectionChanged: (() -> Void)?
    /// Keep selection / handles above the options panel strip.
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

    /// `sourceRect` is top-left origin in display-local points (same as SCK).
    @discardableResult
    func restoreSelection(sourceRect: CGRect) -> Bool {
        let cocoa = CGRect(
            x: sourceRect.minX,
            y: bounds.height - sourceRect.minY - sourceRect.height,
            width: sourceRect.width,
            height: sourceRect.height
        )
        let clamped = clamp(cocoa)
        guard clamped.width >= minSize, clamped.height >= minSize else { return false }
        // Reject if the rect barely fits / was for a very different display size.
        let overlap = clamped.intersection(usableBounds)
        guard overlap.width >= minSize, overlap.height >= minSize else { return false }
        selectionInWindowCoords = clamped
        needsDisplay = true
        onSelectionChanged?()
        return true
    }

    func clearSelection() {
        selectionInWindowCoords = nil
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Leave the bottom strip for the options NSPanel above us.
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

            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.setStrokeColor(Self.selectionBlue.cgColor)
                ctx.setLineWidth(2)
                ctx.setLineDash(phase: 0, lengths: [6, 5])
                ctx.stroke(selection.insetBy(dx: 1, dy: 1))
                ctx.restoreGState()
            }

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
