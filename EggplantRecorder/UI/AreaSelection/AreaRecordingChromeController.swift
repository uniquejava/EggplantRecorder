import AppKit

/// During area recording: pale-blue dashed frame around the capture rect + OMI-style mini control bar below it.
/// Windows are excluded from ScreenCaptureKit via `excludePID`, so they never appear in the MP4.
@MainActor
final class AreaRecordingChromeController {
    private weak var appState: AppState?
    private var borderWindow: AreaRecordingBorderWindow?
    private var controlPanel: AreaRecordingMiniPanel?

    func configure(appState: AppState) {
        self.appState = appState
    }

    var isVisible: Bool { borderWindow?.isVisible == true || controlPanel?.isVisible == true }

    func show(area: AreaSelectionResult) {
        hide()
        guard let screen = NSScreen.screens.first(where: { $0.displayID == area.displayID })
            ?? NSScreen.main
        else { return }

        let globalRect = Self.globalCocoaRect(sourceRect: area.sourceRect, on: screen)

        let border = AreaRecordingBorderWindow(screen: screen, selectionGlobal: globalRect)
        border.orderFrontRegardless()
        borderWindow = border

        let panel = AreaRecordingMiniPanel(appState: appState)
        panel.position(below: globalRect, on: screen)
        panel.orderFrontRegardless()
        controlPanel = panel
        panel.reload()
    }

    func hide() {
        borderWindow?.orderOut(nil)
        borderWindow = nil
        controlPanel?.orderOut(nil)
        controlPanel = nil
    }

    func reload() {
        controlPanel?.reload()
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
