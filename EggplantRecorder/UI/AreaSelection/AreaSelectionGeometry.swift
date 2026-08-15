import CoreGraphics
import Foundation

/// Pure geometry for the Area selection rect, lifted out of `AreaSelectionCanvas` so it can be
/// unit-tested without an NSView, a window, or a display. The canvas passes its own `bounds`,
/// `minSize` and `handleSize` in; nothing here reads view state.
///
/// Pitfall #8 lives in `resizedByDelta`: a handle drag moves the grabbed edge by the delta
/// **from mouseDown**, never "edge = current mouse point". Zero delta must be a no-op.
enum AreaSelectionGeometry {
    /// Keeps `rect` at least `minSize` on both axes, no larger than `bounds`, and fully inside
    /// `bounds` — an out-of-bounds rect slides back in rather than being shrunk.
    static func clamp(_ rect: CGRect, in bounds: CGRect, minSize: CGFloat) -> CGRect {
        var r = rect
        r.size.width = max(minSize, min(r.width, bounds.width))
        r.size.height = max(minSize, min(r.height, bounds.height))
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        return r
    }

    /// Move the grabbed edge(s) by drag delta from mouseDown — zero movement keeps the rect
    /// unchanged. Dragging an edge past its opposite edge flips the rect rather than inverting it.
    static func resizedByDelta(
        _ start: CGRect,
        handle: AreaHandlePosition,
        dx: CGFloat,
        dy: CGFloat
    ) -> CGRect {
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

    /// Grow a too-small rect up to `minSize`, keeping it inside `bounds` (mouseUp fixup for a click
    /// or a tiny drag).
    ///
    /// Note the origin barely moves: each axis's new origin is derived from `midX`/`midY` *after*
    /// the size has already been raised, so a zero-size click ends up as the rect's bottom-left
    /// corner rather than its centre. Preserved as-is — this is long-standing behaviour.
    static func enforceMinimum(_ rect: CGRect, in bounds: CGRect, minSize: CGFloat) -> CGRect {
        var r = rect
        if r.width < minSize {
            r.size.width = minSize
            r.origin.x = min(max(bounds.minX, r.midX - minSize / 2), bounds.maxX - minSize)
        }
        if r.height < minSize {
            r.size.height = minSize
            r.origin.y = min(max(bounds.minY, r.midY - minSize / 2), bounds.maxY - minSize)
        }
        return r
    }

    static func handlePoint(_ handle: AreaHandlePosition, in selection: CGRect) -> CGPoint {
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

    static func handleRect(
        _ handle: AreaHandlePosition,
        in selection: CGRect,
        handleSize: CGFloat
    ) -> CGRect {
        let p = handlePoint(handle, in: selection)
        return CGRect(
            x: p.x - handleSize / 2,
            y: p.y - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
    }

    /// Handle slop, so a near-miss on a small dot still grabs the edge instead of moving the rect.
    static let hitSlop: CGFloat = 4

    static func hitHandle(
        at point: CGPoint,
        in selection: CGRect,
        handleSize: CGFloat
    ) -> AreaHandlePosition? {
        for handle in AreaHandlePosition.allCases {
            let target = handleRect(handle, in: selection, handleSize: handleSize)
                .insetBy(dx: -hitSlop, dy: -hitSlop)
            if target.contains(point) {
                return handle
            }
        }
        return nil
    }
}
