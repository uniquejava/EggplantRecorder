import AppKit

/// During area recording: pale-blue dashed frame around the capture rect + OMI-style mini control bar below it.
/// Windows are excluded from ScreenCaptureKit via `excludePID`, so they never appear in the MP4.
@MainActor
final class AreaRecordingChromeController {
    private weak var appState: AppState?
    private var borderWindow: AreaRecordingBorderWindow?
    private var controlPanel: AreaRecordingMiniPanel?

    func configure(appState: AppState) {
        self.appState = appState
    }

    var isVisible: Bool { borderWindow?.isVisible == true || controlPanel?.isVisible == true }

    func show(area: AreaSelectionResult) {
        hide()
        guard let screen = NSScreen.screens.first(where: { $0.displayID == area.displayID })
            ?? NSScreen.main
        else { return }

        let globalRect = Self.globalCocoaRect(sourceRect: area.sourceRect, on: screen)

        let border = AreaRecordingBorderWindow(screen: screen, selectionGlobal: globalRect)
        border.orderFrontRegardless()
        borderWindow = border

        let panel = AreaRecordingMiniPanel(appState: appState)
        panel.position(below: globalRect, on: screen)
        panel.orderFrontRegardless()
        controlPanel = panel
        panel.reload()
    }

    func hide() {
        borderWindow?.orderOut(nil)
        borderWindow = nil
        controlPanel?.orderOut(nil)
        controlPanel = nil
    }

    func reload() {
        controlPanel?.reload()
    }

    /// `sourceRect` is top-left origin in display-local points (SCK). Convert to global Cocoa (bottom-left).
    static func globalCocoaRect(sourceRect: CGRect, on screen: NSScreen) -> CGRect {
        let sf = screen.frame
        return CGRect(
            x: sf.minX + sourceRect.minX,
            y: sf.maxY - sourceRect.minY - sourceRect.height,
            width: sourceRect.width,
            height: sourceRect.height
        )
    }
}

// MARK: - Border (click-through)

private final class AreaRecordingBorderWindow: NSWindow {
    private let canvas: AreaRecordingBorderCanvas

    init(screen: NSScreen, selectionGlobal: CGRect) {
        let local = CGRect(
            x: selectionGlobal.minX - screen.frame.minX,
            y: selectionGlobal.minY - screen.frame.minY,
            width: selectionGlobal.width,
            height: selectionGlobal.height
        )
        canvas = AreaRecordingBorderCanvas(frame: NSRect(origin: .zero, size: screen.frame.size))
        canvas.selectionLocal = local

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        contentView = canvas
    }
}

private final class AreaRecordingBorderCanvas: NSView {
    /// Soft sky blue matching Area selection chrome (~#A3C1F0).
    private static let selectionBlue = NSColor(srgbRed: 163 / 255, green: 193 / 255, blue: 240 / 255, alpha: 1)

    var selectionLocal: CGRect? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let selection = selectionLocal, selection.width > 1, selection.height > 1 else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setStrokeColor(Self.selectionBlue.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [6, 5])
        ctx.stroke(selection.insetBy(dx: 1, dy: 1))
        ctx.restoreGState()
    }
}

// MARK: - Mini control panel

private final class AreaRecordingMiniPanel: NSPanel {
    private weak var appState: AppState?
    private let chrome = AreaRecordingMiniBarView()

    init(appState: AppState?) {
        self.appState = appState
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 292, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false

        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.onLayoutChange = { [weak self] in
            self?.syncContentSize(keepTopFixed: true)
        }
        chrome.onPause = { [weak self] in
            Task { @MainActor in
                self?.appState?.togglePause()
                self?.reload()
            }
        }
        chrome.onStop = { [weak self] in
            Task { @MainActor in
                await self?.appState?.stopRecording()
            }
        }
        chrome.onRestart = { [weak self] in
            Task { @MainActor in
                await self?.appState?.restartRecording()
            }
        }
        chrome.onCancel = { [weak self] in
            Task { @MainActor in
                await self?.appState?.cancelRecording()
            }
        }

        let root = NSView()
        root.wantsLayer = true
        contentView = root
        root.addSubview(chrome)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: root.topAnchor),
            chrome.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
    }

    func position(below selectionGlobal: CGRect, on screen: NSScreen) {
        syncContentSize(keepTopFixed: false)
        let size = chrome.fittingSize

        let gap: CGFloat = 10
        var origin = CGPoint(
            x: selectionGlobal.midX - size.width / 2,
            y: selectionGlobal.minY - gap - size.height
        )
        // Flip above the selection when there isn't room below.
        if origin.y < screen.visibleFrame.minY + 4 {
            origin.y = selectionGlobal.maxY + gap
        }
        let maxX = screen.visibleFrame.maxX - size.width - 4
        let minX = screen.visibleFrame.minX + 4
        origin.x = min(max(origin.x, minX), maxX)

        setFrameOrigin(origin)
    }

    func reload() {
        guard let appState else { return }
        chrome.update(
            elapsed: appState.elapsedSeconds,
            isPaused: appState.isPaused
        )
    }

    /// Keep the bar’s top + trailing edges stable so Cancel doesn’t jump when the banner appears.
    private func syncContentSize(keepTopFixed: Bool) {
        let size = chrome.fittingSize
        let old = frame
        setContentSize(size)
        var origin = NSPoint(x: old.maxX - size.width, y: old.origin.y)
        if keepTopFixed {
            origin.y = old.maxY - size.height
        }
        setFrameOrigin(origin)
    }
}

// MARK: - Bar view (OMI: timer + circular buttons)

private final class AreaRecordingMiniBarView: NSView {
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
private final class CancelConfirmBannerView: NSView {
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
