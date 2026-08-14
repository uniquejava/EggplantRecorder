import AppKit

/// OMI: timer + circular buttons. Cancel arms a confirm chip, then discards on second click.
final class AreaRecordingMiniBarView: NSView {
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onRestart: (() -> Void)?
    var onCancel: (() -> Void)?
    var onLayoutChange: (() -> Void)?

    private let barContainer = NSView()
    private let timerLabel = NSTextField(labelWithString: "00:00:00")
    private let annotateButton = NSButton()
    private let stopButton = NSButton()
    private let pauseButton = NSButton()
    private let restartButton = NSButton()
    private let cancelButton = NSButton()
    private let effect = NSVisualEffectView()
    private let confirmBanner = CancelConfirmBannerView()

    private var cancelArmed = false
    private var armResetWorkItem: DispatchWorkItem?

    private static let barHeight: CGFloat = 44
    private static let bannerGap: CGFloat = 6
    private static let bannerHeight: CGFloat = 28
    private static let bannerWidth: CGFloat = 372
    private static let buttonSize: CGFloat = 30
    private static let barWidth: CGFloat = 292

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        barContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(barContainer)

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 22
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false
        barContainer.addSubview(effect)

        let border = NSView()
        border.wantsLayer = true
        border.layer?.cornerRadius = 22
        border.layer?.borderWidth = 1
        border.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        border.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        barContainer.addSubview(border)

        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timerLabel.textColor = .white
        timerLabel.alignment = .left
        timerLabel.isEditable = false
        timerLabel.isBezeled = false
        timerLabel.drawsBackground = false

        configureCircleButton(
            annotateButton,
            image: Self.circleSymbolIcon("pencil", tint: NSColor.black.withAlphaComponent(0.45)),
            tooltip: "Annotate (coming soon)"
        )
        annotateButton.isEnabled = false
        annotateButton.alphaValue = 0.55

        configureCircleButton(stopButton, image: Self.stopIcon(), tooltip: "Stop")
        stopButton.target = self
        stopButton.action = #selector(stopTapped)

        configureCircleButton(
            pauseButton,
            image: Self.circleSymbolIcon("pause.fill"),
            tooltip: "Pause"
        )
        pauseButton.target = self
        pauseButton.action = #selector(pauseTapped)

        configureCircleButton(
            restartButton,
            image: Self.circleSymbolIcon("arrow.counterclockwise"),
            tooltip: "Restart"
        )
        restartButton.target = self
        restartButton.action = #selector(restartTapped)

        configureCircleButton(
            cancelButton,
            image: Self.circleSymbolIcon("xmark"),
            tooltip: "Cancel"
        )
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)

        let stack = NSStackView(views: [
            timerLabel, annotateButton, stopButton, pauseButton, restartButton, cancelButton,
        ])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 14, bottom: 7, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        barContainer.addSubview(stack)

        let buttons = [annotateButton, stopButton, pauseButton, restartButton, cancelButton]
        for button in buttons {
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentHuggingPriority(.required, for: .vertical)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        confirmBanner.translatesAutoresizingMaskIntoConstraints = false
        confirmBanner.isHidden = true
        addSubview(confirmBanner)

        NSLayoutConstraint.activate([
            barContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            barContainer.topAnchor.constraint(equalTo: topAnchor),
            barContainer.widthAnchor.constraint(equalToConstant: Self.barWidth),
            barContainer.heightAnchor.constraint(equalToConstant: Self.barHeight),

            effect.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: barContainer.trailingAnchor),
            effect.topAnchor.constraint(equalTo: barContainer.topAnchor),
            effect.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor),
            border.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: barContainer.trailingAnchor),
            border.topAnchor.constraint(equalTo: barContainer.topAnchor),
            border.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: barContainer.trailingAnchor),
            stack.topAnchor.constraint(equalTo: barContainer.topAnchor),
            stack.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor),

            confirmBanner.topAnchor.constraint(equalTo: barContainer.bottomAnchor, constant: Self.bannerGap),
            confirmBanner.trailingAnchor.constraint(equalTo: barContainer.trailingAnchor),
            confirmBanner.heightAnchor.constraint(equalToConstant: Self.bannerHeight),
            confirmBanner.widthAnchor.constraint(equalToConstant: Self.bannerWidth),

            annotateButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            annotateButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),
            stopButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            stopButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),
            pauseButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            pauseButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),
            restartButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            restartButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),
            cancelButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            cancelButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])
    }

    private func configureCircleButton(_ button: NSButton, image: NSImage, tooltip: String) {
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tooltip
        button.image = image
    }

    /// White disc + SF Symbol, drawn as one square image so layout never flattens the circle.
    private static func circleSymbolIcon(
        _ symbol: String,
        tint: NSColor = NSColor.black.withAlphaComponent(0.78)
    ) -> NSImage {
        let side = buttonSize
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect).fill()

            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
            guard let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            else { return true }

            let iconSize = symbolImage.size
            let iconRect = NSRect(
                x: (side - iconSize.width) / 2,
                y: (side - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            symbolImage.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func stopIcon() -> NSImage {
        let side = buttonSize
        let size = NSSize(width: side, height: side)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect).fill()
            NSColor.systemRed.setFill()
            let square = NSRect(x: 9, y: 9, width: 12, height: 12)
            NSBezierPath(roundedRect: square, xRadius: 2.5, yRadius: 2.5).fill()
            return true
        }
    }

    func update(elapsed: TimeInterval, isPaused: Bool) {
        timerLabel.stringValue = MediaProbe.formatClock(elapsed)
        let symbol = isPaused ? "play.fill" : "pause.fill"
        let tip = isPaused ? "Resume" : "Pause"
        pauseButton.image = Self.circleSymbolIcon(symbol)
        pauseButton.toolTip = tip
    }

    override var fittingSize: NSSize {
        if cancelArmed {
            // Banner hangs left from the cancel (trailing) side; panel must be wide enough.
            return NSSize(
                width: Self.bannerWidth,
                height: Self.barHeight + Self.bannerGap + Self.bannerHeight
            )
        }
        return NSSize(width: Self.barWidth, height: Self.barHeight)
    }

    private func clearCancelArm(notify: Bool = true) {
        armResetWorkItem?.cancel()
        armResetWorkItem = nil
        guard cancelArmed else { return }
        cancelArmed = false
        confirmBanner.isHidden = true
        if notify { onLayoutChange?() }
    }

    private func armCancel() {
        cancelArmed = true
        confirmBanner.isHidden = false
        onLayoutChange?()

        armResetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.clearCancelArm()
        }
        armResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    @objc private func pauseTapped() {
        clearCancelArm()
        onPause?()
    }

    @objc private func stopTapped() {
        clearCancelArm()
        onStop?()
    }

    @objc private func restartTapped() {
        clearCancelArm()
        onRestart?()
    }

    @objc private func cancelTapped() {
        if cancelArmed {
            clearCancelArm(notify: false)
            onCancel?()
        } else {
            armCancel()
        }
    }
}

/// OMI-style light confirm chip under the Cancel button.
final class CancelConfirmBannerView: NSView {
    private let label = NSTextField(wrappingLabelWithString:
        "Cancel will discard the recorded content, click again to confirm"
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor(srgbRed: 0.92, green: 0.92, blue: 0.93, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.black.withAlphaComponent(0.35).cgColor

        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .black
        label.alignment = .left
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
