import AppKit
import SwiftUI

@MainActor
final class EditorController {
    private weak var appState: AppState?
    private var window: NSWindow?
    private var hosting: NSHostingController<EditorView>?
    private var model: EditorModel?

    func configure(appState: AppState) {
        self.appState = appState
    }

    func show(entry: RecordingEntry) {
        let created = window == nil
        if window == nil {
            createWindow()
        }
        install(entry: entry)
        NSApp.setActivationPolicy(.regular)
        window?.title = "Edit — \(entry.name)"
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        if created {
            // After the window is on a screen — cascading would otherwise pin it top-left.
            placeOnScreen(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        model?.teardown()
        model = nil
        window?.orderOut(nil)
        if NSApp.windows.filter({ $0.isVisible && $0 !== window }).isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func install(entry: RecordingEntry) {
        model?.teardown()
        let model = EditorModel(path: entry.path, name: entry.name)
        model.onExported = { [weak self] path in
            self?.handleExported(path)
        }
        self.model = model
        let root = EditorView(model: model)
        if let hosting {
            hosting.rootView = root
            hosting.view.focusRingType = .none
        } else if let window {
            let hosting = NSHostingController(rootView: root)
            hosting.view.appearance = NSAppearance(named: .aqua)
            hosting.view.focusRingType = .none
            self.hosting = hosting
            window.contentViewController = hosting
        }
    }

    private func handleExported(_ path: String) {
        guard let appState else { return }
        hide()
        appState.highlightPath = path
        Task {
            await appState.refreshRecordings()
            appState.filesList.show(highlightPath: path)
        }
    }

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit"
        window.contentMinSize = NSSize(width: 1000, height: 640)
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = EditorChrome.nsWindow
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .line
        window.isReleasedWhenClosed = false
        window.delegate = EditorWindowDelegate.shared
        EditorWindowDelegate.shared.onClose = { [weak self] in
            self?.hide()
        }
        self.window = window
    }

    /// Fill the visible screen with a small margin, origin centered.
    private func placeOnScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            window.setContentSize(NSSize(width: 1440, height: 900))
            window.center()
            return
        }
        let vis = screen.visibleFrame
        let margin: CGFloat = 16
        var frame = vis.insetBy(dx: margin, dy: margin)
        frame.origin.x = vis.midX - frame.width / 2
        frame.origin.y = vis.midY - frame.height / 2
        window.setFrame(frame, display: true)
    }
}

private final class EditorWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = EditorWindowDelegate()
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
