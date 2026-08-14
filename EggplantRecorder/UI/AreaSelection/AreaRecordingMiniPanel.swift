import AppKit

final class AreaRecordingMiniPanel: NSPanel {
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
