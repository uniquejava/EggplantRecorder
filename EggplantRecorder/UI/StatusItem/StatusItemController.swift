import AppKit

@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private weak var appState: AppState?
    private var controlBar: RecordingControlBarView?
    private var embeddedContainer: NSView?

    func install(appState: AppState) {
        self.appState = appState
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.image = RecorderGlyph.menuBar()
            button.imagePosition = .imageOnly
            button.toolTip = "EggplantRecorder"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        enterIdleMode()
    }

    func enterIdleMode() {
        guard let item = statusItem, let button = item.button else { return }
        clearEmbedded()
        item.length = NSStatusItem.variableLength
        button.image = RecorderGlyph.menuBar()
        button.imagePosition = .imageOnly
        button.title = ""
        button.isEnabled = true
        controlBar = nil
    }

    func enterRecordingMode() {
        guard let item = statusItem, let button = item.button, let appState else { return }
        button.image = nil
        button.title = ""
        // Keep enabled so embedded Pause/Stop receive clicks; action is no-op while recording.
        button.isEnabled = true

        let bar = RecordingControlBarView(appState: appState)
        controlBar = bar

        let container = NSView(frame: .zero)
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        clearEmbedded()
        button.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            container.topAnchor.constraint(equalTo: button.topAnchor),
            container.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        embeddedContainer = container

        item.length = bar.preferredWidth
        bar.onSizeChange = { [weak item, weak bar] in
            guard let item, let bar else { return }
            item.length = bar.preferredWidth
        }
    }

    func refreshRecordingControls() {
        controlBar?.reload()
        if let bar = controlBar, let item = statusItem {
            item.length = bar.preferredWidth
        }
    }

    private func clearEmbedded() {
        embeddedContainer?.removeFromSuperview()
        embeddedContainer = nil
        statusItem?.button?.subviews.forEach { $0.removeFromSuperview() }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let appState, appState.phase != .recording, appState.phase != .countdown else { return }
        let menu = makeIdleMenu()
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    private func makeIdleMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Record Screen", action: #selector(recordScreen), keyEquivalent: "")
        menu.addItem(withTitle: "Record Area", action: #selector(recordArea), keyEquivalent: "")
        menu.addItem(withTitle: "Record Window Area", action: #selector(recordWindowArea), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Record Window", action: #selector(recordWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Files List", action: #selector(showFiles), keyEquivalent: "")
        menu.addItem(.separator())
        let prefs = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefs.keyEquivalentModifierMask = [.command]
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit EggplantRecorder", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil {
            item.target = self
        }
        return menu
    }

    @objc private func recordScreen() {
        appState?.showOptions(mode: .screen)
    }

    @objc private func recordArea() {
        appState?.showAreaSelection()
    }

    @objc private func recordWindow() {
        appState?.showWindowSelection()
    }

    @objc private func recordWindowArea() {
        appState?.showWindowAreaSelection()
    }

    @objc private func showFiles() {
        appState?.showFilesList()
    }

    @objc private func openPreferences() {
        appState?.openPreferences()
    }

    @objc private func quit() {
        appState?.quit()
    }
}
