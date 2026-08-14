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
        if window == nil {
            createWindow()
        }
        install(entry: entry)
        NSApp.setActivationPolicy(.regular)
        window?.title = "Edit — \(entry.name)"
        window?.makeKeyAndOrderFront(nil)
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
        } else if let window {
            let hosting = NSHostingController(rootView: root)
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
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit"
        window.setContentSize(NSSize(width: 960, height: 640))
        window.contentMinSize = NSSize(width: 720, height: 460)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = EditorWindowDelegate.shared
        EditorWindowDelegate.shared.onClose = { [weak self] in
            self?.hide()
        }
        self.window = window
    }
}

private final class EditorWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = EditorWindowDelegate()
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
