import AppKit

enum AreaHandlePosition: CaseIterable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
}

final class AreaSelectionCanvas: NSView {
    var onBeginEditing: (() -> Void)?
    var onSelectionChanged: (() -> Void)?
    /// When true, mouse does not create / move / resize the selection (countdown).
    var isLocked = false

    private(set) var selectionInWindowCoords: CGRect?
    private var dragKind: DragKind = .none
    private var dragStart: CGPoint = .zero
    private var selectionAtDragStart: CGRect = .zero
    private let handleSize: CGFloat = 11
    private let minSize: CGFloat = 40

    private enum DragKind {
        case none
        case creating
        case moving
        case resizing(AreaHandlePosition)
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    func installDefaultSelection() {
        let area = bounds
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
        let overlap = clamped.intersection(bounds)
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

    override func draw(_ dirtyRect: NSRect) {
        if let selection = selectionInWindowCoords {
            let dim = NSBezierPath(rect: bounds)
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.45).setFill()
            dim.fill()

            if let ctx = NSGraphicsContext.current?.cgContext {
                SelectionChrome.strokeDashedRect(selection, in: ctx)
            }

            for handle in AreaHandlePosition.allCases {
                let rect = handleRect(handle, in: selection)
                SelectionChrome.blue.setFill()
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
        guard !isLocked else { return }
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
        guard !isLocked else { return }
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
        guard !isLocked else { return }
        if let selection = selectionInWindowCoords, selection.width < minSize || selection.height < minSize {
            var r = selection
            let area = bounds
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
        let area = bounds
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
    private func resizedByDelta(_ start: CGRect, handle: AreaHandlePosition, dx: CGFloat, dy: CGFloat) -> CGRect {
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

    private func handleRect(_ handle: AreaHandlePosition, in selection: CGRect) -> CGRect {
        let p = handlePoint(handle, in: selection)
        return CGRect(
            x: p.x - handleSize / 2,
            y: p.y - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
    }

    private func handlePoint(_ handle: AreaHandlePosition, in selection: CGRect) -> CGPoint {
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

    private func hitHandle(at point: CGPoint, in selection: CGRect) -> AreaHandlePosition? {
        for handle in AreaHandlePosition.allCases {
            if handleRect(handle, in: selection).insetBy(dx: -4, dy: -4).contains(point) {
                return handle
            }
        }
        return nil
    }
}
