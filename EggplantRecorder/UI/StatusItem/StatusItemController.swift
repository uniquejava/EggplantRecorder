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
        guard let appState, appState.phase != .recording else { return }
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
        menu.addItem(withTitle: "Record Window", action: #selector(recordWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Files List", action: #selector(showFiles), keyEquivalent: "")
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

    @objc private func showFiles() {
        appState?.showFilesList()
    }

    @objc private func quit() {
        appState?.quit()
    }
}

final class RecordingControlBarView: NSView {
    private weak var appState: AppState?
    var onSizeChange: (() -> Void)?

    private let pauseButton = NSButton()
    private let stopButton = NSButton()
    private let timerLabel = NSTextField(labelWithString: "00:00:00")

    init(appState: AppState) {
        self.appState = appState
        super.init(frame: NSRect(x: 0, y: 0, width: 128, height: 22))
        wantsLayer = true
        build()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        pauseButton.isBordered = false
        pauseButton.imagePosition = .imageOnly
        pauseButton.target = self
        pauseButton.action = #selector(togglePause)
        pauseButton.toolTip = "Pause / Resume"

        stopButton.isBordered = false
        stopButton.imagePosition = .imageOnly
        stopButton.target = self
        stopButton.action = #selector(stop)
        stopButton.toolTip = "Stop"

        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timerLabel.textColor = .labelColor
        timerLabel.alignment = .left
        timerLabel.isEditable = false
        timerLabel.isBezeled = false
        timerLabel.drawsBackground = false

        let stack = NSStackView(views: [pauseButton, stopButton, timerLabel])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            pauseButton.widthAnchor.constraint(equalToConstant: 18),
            pauseButton.heightAnchor.constraint(equalToConstant: 18),
            stopButton.widthAnchor.constraint(equalToConstant: 16),
            stopButton.heightAnchor.constraint(equalToConstant: 16),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    func reload() {
        guard let appState else { return }
        let paused = appState.isPaused
        let pauseSymbol = paused ? "play.fill" : "pause.fill"
        pauseButton.image = NSImage(
            systemSymbolName: pauseSymbol,
            accessibilityDescription: paused ? "Resume" : "Pause"
        )
        pauseButton.contentTintColor = .labelColor

        let stopImage = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            NSColor.systemRed.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2).fill()
            return true
        }
        stopImage.isTemplate = false
        stopButton.image = stopImage

        timerLabel.stringValue = MediaProbe.formatClock(appState.elapsedSeconds)
        invalidateIntrinsicContentSize()
        onSizeChange?()
    }

    override var intrinsicContentSize: NSSize {
        let timerWidth = max(timerLabel.intrinsicContentSize.width, 58)
        return NSSize(width: 4 + 18 + 6 + 16 + 6 + timerWidth + 6, height: 22)
    }

    var preferredWidth: CGFloat { intrinsicContentSize.width }

    @objc private func togglePause() {
        Task { @MainActor in
            appState?.togglePause()
            reload()
        }
    }

    @objc private func stop() {
        Task { @MainActor in
            await appState?.stopRecording()
        }
    }
}
