import AppKit
import SwiftUI

@MainActor
final class FilesListController {
    private weak var appState: AppState?
    private var window: NSWindow?

    func configure(appState: AppState) {
        self.appState = appState
    }

    func show(highlightPath: String?) {
        guard let appState else { return }
        if window == nil {
            createWindow(appState: appState)
        }
        if let highlightPath {
            appState.highlightPath = highlightPath
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { await appState.refreshRecordings() }
    }

    func hide() {
        window?.orderOut(nil)
        if NSApp.windows.filter({ $0.isVisible && $0 !== window }).isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func createWindow(appState: AppState) {
        let root = FilesListView(appState: appState)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Files List"
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 800, height: 480))
        window.contentMinSize = NSSize(width: 800, height: 320)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = FilesListWindowDelegate.shared
        FilesListWindowDelegate.shared.onClose = { [weak self] in
            self?.hide()
        }
        self.window = window
    }
}

private final class FilesListWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = FilesListWindowDelegate()
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
