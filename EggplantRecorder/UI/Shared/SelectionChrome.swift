import AppKit

/// Shared pale-blue dashed chrome used by Area pick, Window pick, and Area recording frame.
enum SelectionChrome {
    static let blue = NSColor(srgbRed: 163 / 255, green: 193 / 255, blue: 240 / 255, alpha: 1)

    static func strokeDashedRect(_ rect: CGRect, in ctx: CGContext, lineWidth: CGFloat = 2) {
        ctx.saveGState()
        ctx.setStrokeColor(blue.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineDash(phase: 0, lengths: [6, 5])
        ctx.stroke(rect.insetBy(dx: 1, dy: 1))
        ctx.restoreGState()
    }
}
