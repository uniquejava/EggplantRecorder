import AppKit
import SwiftUI

@MainActor
final class OptionsBarController {
    private weak var appState: AppState?
    private var panel: KeyablePanel?
    private var hostingView: NSHostingView<OptionsBarView>?
    private var model: OptionsBarModel?

    func configure(appState: AppState) {
        self.appState = appState
    }

    func show(mode: RecordingKind, anchorRect: CGRect? = nil) {
        guard let appState else { return }
        if panel == nil {
            createPanel(appState: appState)
        }
        // `anchorRect` ignored — panel always opens bottom-center (user can drag).
        _ = anchorRect
        model?.prepare(mode: mode)
        resizeToFit()
        positionPanelBottomCenter()
        panel?.alphaValue = 0
        panel?.level = .statusBar
        panel?.orderFrontRegardless()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.resizeToFit()
            self?.positionPanelBottomCenter()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel?.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    func showError(_ message: String) {
        model?.bannerMessage = message
        if panel?.isVisible == true {
            resizeToFit()
        } else if let mode = model?.mode {
            show(mode: mode)
        }
    }

    private func createPanel(appState: AppState) {
        let model = OptionsBarModel(appState: appState)
        self.model = model
        let root = OptionsBarView(model: model)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 622, height: 230)
        self.hostingView = hosting

        let panel = KeyablePanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
        self.panel = panel

        model.onClose = { [weak self] in
            self?.appState?.hideOptions()
        }
        model.onRecord = { [weak self] config in
            Task { @MainActor in
                await self?.appState?.startRecording(config: config)
            }
        }
        model.onContentSizeMayChange = { [weak self] in
            // Keep current origin (user may have dragged); only grow/shrink height.
            self?.resizeToFit(preserveOrigin: true)
        }
    }

    private func resizeToFit(preserveOrigin: Bool = true) {
        guard let panel, let hostingView else { return }
        let oldFrame = panel.frame
        hostingView.layoutSubtreeIfNeeded()
        var size = hostingView.fittingSize
        if size.width < 10 || size.height < 10 {
            size = NSSize(width: 622, height: 230)
        }
        size.height = min(max(size.height, 230), 320)
        size.width = min(max(size.width, 622), 680)
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        if preserveOrigin {
            // Origin is bottom-left; keep bottom edge stable when height changes.
            panel.setFrameOrigin(NSPoint(x: oldFrame.minX, y: oldFrame.maxY - panel.frame.height))
        }
    }

    private func positionPanelBottomCenter() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let size = panel.frame.size
        let x = screen.frame.midX - size.width / 2
        // OMI: ~16pt above the physical bottom edge of the display.
        let y = screen.frame.minY + 16
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
