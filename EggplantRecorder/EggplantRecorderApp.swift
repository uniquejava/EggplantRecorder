import AppKit
import Quartz
import SwiftUI

extension Notification.Name {
    static let openAppPreferences = Notification.Name("EggplantRecorder.openAppPreferences")
}

@main
struct EggplantRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Invisible MenuBarExtra hosts openSettings bridge. Real tray is AppKit NSStatusItem.
        MenuBarExtra(isInserted: .constant(false)) {
            EmptyView()
        } label: {
            EmptyView()
                .background(PreferencesEnvironmentBridge())
        }

        Settings {
            SettingsView()
                .onAppear {
                    AppActivation.preferForeground()
                }
                .onDisappear {
                    AppActivation.preferBackgroundIfIdle()
                }
        }
    }
}

/// Bridges AppKit status menus → SwiftUI `openSettings` (required; `showSettingsWindow:` is rejected).
private struct PreferencesEnvironmentBridge: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                OpenSettingsGateway.shared.open = { [openSettings] in
                    openSettings()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAppPreferences)) { _ in
                OpenSettingsGateway.shared.open?()
                AppActivation.preferForeground()
            }
    }
}

@MainActor
enum OpenSettingsGateway {
    static let shared = Gateway()
    final class Gateway {
        var open: (() -> Void)?
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Ignores the spurious reopen that macOS sends during cold `open`/Xcode Run.
    private var readyForReopen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppActivation.applyPreferredPolicy()
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
