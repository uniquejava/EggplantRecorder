import AppKit
import Quartz
import SwiftUI

@main
struct EggplantRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Status item is AppKit-owned. Avoid Settings/WindowGroup so launch
        // does not materialize any window — tray icon only.
        MenuBarExtra(isInserted: .constant(false)) {
            EmptyView()
        } label: {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Ignores the spurious reopen that macOS sends during cold `open`/Xcode Run.
    private var readyForReopen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppState.shared.bootstrap()
        QuickLookController.shared.install()
        // Defer so launch-time reopen does not pop Files List.
        DispatchQueue.main.async {
            self.readyForReopen = true
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Menu-bar app: dock/reopen may show Files List, but never on first launch.
        guard readyForReopen, !flag else { return true }
        AppState.shared.showFilesList()
        return true
    }
}
