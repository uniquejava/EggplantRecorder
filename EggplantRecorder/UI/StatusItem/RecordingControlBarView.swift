import AppKit

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
        // Stop/Pause go inert while a stop is finalizing — the tap that used to land here
        // during `recorder.stop()`'s await double-finished the writer (audit #1).
        let transitioning = appState.phase.isTransitioning
        pauseButton.isEnabled = !transitioning
        stopButton.isEnabled = !transitioning
        pauseButton.alphaValue = transitioning ? 0.4 : 1
        stopButton.alphaValue = transitioning ? 0.4 : 1

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

        let showTimer = AppPreferences.shared.displayRecordingTime
        timerLabel.isHidden = !showTimer
        if showTimer {
            timerLabel.stringValue = MediaProbe.formatClock(appState.elapsedSeconds)
        }
        invalidateIntrinsicContentSize()
        onSizeChange?()
    }

    override var intrinsicContentSize: NSSize {
        let showTimer = !timerLabel.isHidden
        let timerWidth = showTimer ? max(timerLabel.intrinsicContentSize.width, 58) : 0
        let timerGap: CGFloat = showTimer ? 6 : 0
        return NSSize(width: 4 + 18 + 6 + 16 + timerGap + timerWidth + 6, height: 22)
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
