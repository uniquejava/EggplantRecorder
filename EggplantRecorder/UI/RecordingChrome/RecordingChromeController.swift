import AppKit

/// What the in-recording chrome frames.
enum RecordingChromeTarget {
    case area(AreaSelectionResult)
    /// Window recording: the frame is re-read every tick so the chrome follows the window.
    case window(WindowHit)
}

/// During area / window recording: pale-blue dashed frame around the capture rect + OMI-style
/// mini control bar below it.
/// Area capture excludes these windows from ScreenCaptureKit via `excludePID`; window capture uses
/// `desktopIndependentWindow`, which only sees the target window. Either way they never appear in the MP4.
@MainActor
final class RecordingChromeController {
    private weak var appState: AppState?
    private var borderWindow: RecordingBorderWindow?
    private var controlPanel: RecordingMiniPanel?
    /// Non-nil while framing a window, so `reload()` knows to follow it.
    private var followedWindowID: CGWindowID?
    private var framedRect: CGRect?

    func configure(appState: AppState) {
        self.appState = appState
    }

    var isVisible: Bool { borderWindow?.isVisible == true || controlPanel?.isVisible == true }

    func show(target: RecordingChromeTarget) {
        hide()
        switch target {
        case .area(let area):
            guard let screen = NSScreen.screens.first(where: { $0.displayID == area.displayID })
                ?? NSScreen.main
            else { return }
            present(framing: Self.globalCocoaRect(sourceRect: area.sourceRect, on: screen), on: screen)
        case .window(let hit):
            followedWindowID = hit.windowID
            // The window may have moved between the pick and the countdown finishing.
            let rect = WindowHitTester.liveFrame(of: hit.windowID) ?? hit.frame
            guard let screen = Self.screen(bestMatching: rect) else { return }
            present(framing: rect, on: screen)
        }
    }

    func hide() {
        borderWindow?.orderOut(nil)
        borderWindow = nil
        controlPanel?.orderOut(nil)
        controlPanel = nil
        followedWindowID = nil
        framedRect = nil
    }

    func reload() {
        followWindowIfNeeded()
        controlPanel?.reload()
    }

    private func present(framing rect: CGRect, on screen: NSScreen) {
        let border = RecordingBorderWindow(screen: screen, framedGlobal: rect)
        border.orderFrontRegardless()
        borderWindow = border

        let panel = RecordingMiniPanel(appState: appState)
        panel.position(below: rect, on: screen)
        panel.orderFrontRegardless()
        controlPanel = panel
        panel.reload()

        framedRect = rect
    }

    /// Keep the frame + mini bar glued to the recorded window as the user moves or resizes it.
    private func followWindowIfNeeded() {
        guard let followedWindowID else { return }
        guard let rect = WindowHitTester.liveFrame(of: followedWindowID) else {
            // Window closed, minimized, or on another Space — drop the frame but keep the controls.
            borderWindow?.orderOut(nil)
            borderWindow = nil
            framedRect = nil
            return
        }
        guard rect != framedRect else { return }
        framedRect = rect
        guard let screen = Self.screen(bestMatching: rect) else { return }

        if let borderWindow {
            borderWindow.reframe(framedGlobal: rect, on: screen)
        } else {
            let border = RecordingBorderWindow(screen: screen, framedGlobal: rect)
            border.orderFrontRegardless()
            borderWindow = border
        }
        controlPanel?.position(below: rect, on: screen)
    }

    /// The screen showing most of `rect` — a dragged window can straddle two displays.
    private static func screen(bestMatching rect: CGRect) -> NSScreen? {
        let overlapping = NSScreen.screens.max { lhs, rhs in
            area(of: lhs.frame.intersection(rect)) < area(of: rhs.frame.intersection(rect))
        }
        if let overlapping, area(of: overlapping.frame.intersection(rect)) > 0 {
            return overlapping
        }
        return NSScreen.main
    }

    private static func area(of rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    /// `sourceRect` is top-left origin in display-local points (SCK). Convert to global Cocoa (bottom-left).
    static func globalCocoaRect(sourceRect: CGRect, on screen: NSScreen) -> CGRect {
        let sf = screen.frame
        return CGRect(
            x: sf.minX + sourceRect.minX,
            y: sf.maxY - sourceRect.minY - sourceRect.height,
            width: sourceRect.width,
            height: sourceRect.height
        )
    }
}
