import AppKit

/// Compact timer + circular controls during Area recording.
/// Cancel arms a confirm chip, then discards on second click.
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
    private let confirmBanner = CancelConfirmBannerView()
    private var barWidthConstraint: NSLayoutConstraint?

    private var cancelArmed = false
    private var armResetWorkItem: DispatchWorkItem?
    private var showsTimer = true

    private static let barHeight: CGFloat = 34
    private static let bannerGap: CGFloat = 5
    private static let bannerHeight: CGFloat = 24
    private static let bannerWidth: CGFloat = 320
    private static let buttonSize: CGFloat = 24
    private static let barWidthWithTimer: CGFloat = 236
    private static let barWidthWithoutTimer: CGFloat = 172
    private static let cornerRadius: CGFloat = 8
    /// Style B charcoal — matches the options panel.
    private static let panelFill = NSColor(srgbRed: 0.173, green: 0.180, blue: 0.200, alpha: 1)

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

        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.cornerRadius = Self.cornerRadius
        fill.layer?.masksToBounds = true
        fill.layer?.backgroundColor = Self.panelFill.cgColor
        fill.layer?.borderWidth = 1
        fill.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        fill.translatesAutoresizingMaskIntoConstraints = false
        barContainer.addSubview(fill)

        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        timerLabel.textColor = NSColor(srgbRed: 0.910, green: 0.918, blue: 0.929, alpha: 1)
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
        stack.spacing = 6
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 8)
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
            barContainer.heightAnchor.constraint(equalToConstant: Self.barHeight),

            fill.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
            fill.trailingAnchor.constraint(equalTo: barContainer.trailingAnchor),
            fill.topAnchor.constraint(equalTo: barContainer.topAnchor),
            fill.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor),
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
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])
        let width = barContainer.widthAnchor.constraint(equalToConstant: Self.barWidthWithTimer)
        width.isActive = true
        barWidthConstraint = width
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

            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
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
            let inset: CGFloat = 7
            let square = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
            NSBezierPath(roundedRect: square, xRadius: 2, yRadius: 2).fill()
            return true
        }
    }

    func update(elapsed: TimeInterval, isPaused: Bool, showsTimer: Bool = true) {
        if self.showsTimer != showsTimer {
            self.showsTimer = showsTimer
            timerLabel.isHidden = !showsTimer
            barWidthConstraint?.constant = showsTimer ? Self.barWidthWithTimer : Self.barWidthWithoutTimer
            onLayoutChange?()
        }
        if showsTimer {
            timerLabel.stringValue = MediaProbe.formatClock(elapsed)
        }
        let symbol = isPaused ? "play.fill" : "pause.fill"
        let tip = isPaused ? "Resume" : "Pause"
        pauseButton.image = Self.circleSymbolIcon(symbol)
        pauseButton.toolTip = tip
    }

    override var fittingSize: NSSize {
        let barWidth = showsTimer ? Self.barWidthWithTimer : Self.barWidthWithoutTimer
        if cancelArmed {
            // Banner hangs left from the cancel (trailing) side; panel must be wide enough.
            return NSSize(
                width: Self.bannerWidth,
                height: Self.barHeight + Self.bannerGap + Self.bannerHeight
            )
        }
        return NSSize(width: barWidth, height: Self.barHeight)
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

        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
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
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
