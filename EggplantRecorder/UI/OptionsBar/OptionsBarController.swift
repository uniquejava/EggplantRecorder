import AppKit
import SwiftUI

@MainActor
final class OptionsBarController {
    private weak var appState: AppState?
    private var panel: KeyablePanel?
    private var model: OptionsBarModel?

    func configure(appState: AppState) {
        self.appState = appState
    }

    func show(mode: RecordingKind) {
        guard let appState else { return }
        if panel == nil {
            createPanel(appState: appState)
        }
        model?.prepare(mode: mode)
        positionPanel()
        panel?.alphaValue = 0
        panel?.level = .statusBar
        panel?.orderFrontRegardless()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
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
        if panel?.isVisible != true, let mode = model?.mode {
            show(mode: mode)
        }
    }

    private func createPanel(appState: AppState) {
        let model = OptionsBarModel(appState: appState)
        self.model = model
        let root = OptionsBarView(model: model)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 720, height: 88)

        let panel = KeyablePanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
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
    }

    private func positionPanel() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + 28
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
