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
        guard let appState, appState.canBeginSetup else { return }
        let menu = makeIdleMenu()
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    private func makeIdleMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.tr("menu.recordScreen"), action: #selector(recordScreen), keyEquivalent: "")
        menu.addItem(withTitle: L10n.tr("menu.recordArea"), action: #selector(recordArea), keyEquivalent: "")
        menu.addItem(withTitle: L10n.tr("menu.recordWindowArea"), action: #selector(recordWindowArea), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("menu.recordWindow"), action: #selector(recordWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("menu.showFilesList"), action: #selector(showFiles), keyEquivalent: "")
        menu.addItem(.separator())

        let languageMenu = NSMenu()
        for preference in AppLanguagePreference.allCases {
            let item = NSMenuItem(
                title: preference.menuTitle,
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.representedObject = preference.rawValue
            item.state = preference == AppLanguage.preference ? .on : .off
            item.target = self
            languageMenu.addItem(item)
        }
        let languageItem = NSMenuItem(title: L10n.tr("menu.language"), action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        menu.addItem(.separator())
        let prefs = NSMenuItem(
            title: L10n.tr("menu.preferences"),
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefs.keyEquivalentModifierMask = [.command]
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil {
            item.target = self
        }
        return menu
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preference = AppLanguagePreference(rawValue: raw)
        else { return }
        AppLanguage.setPreferenceAndRelaunch(preference)
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
