import AppKit
import CoreGraphics

/// Full-screen dim overlays with a live selection. Options bar is a separate higher-level
/// `NSPanel` (same options UI as Screen / Window) — no Cancel/Continue chrome here.
@MainActor
final class AreaSelectionController {
    private var overlayWindows: [AreaOverlayWindow] = []
    private var activeScreenID: CGDirectDisplayID?
    private var onSelectionChanged: ((AreaSelectionResult?) -> Void)?
    private var onCancel: (() -> Void)?
    private var escapeMonitor: Any?

    var isVisible: Bool { !overlayWindows.isEmpty }

    /// - Parameter preset: Optional display-local SCK `sourceRect` (e.g. from Window Area pick).
    ///   Wins over the remembered last-area when provided.
    func show(
        preset: (displayID: CGDirectDisplayID, sourceRect: CGRect)? = nil,
        onSelectionChanged: @escaping (AreaSelectionResult?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        hide()
        self.onSelectionChanged = onSelectionChanged
        self.onCancel = onCancel

        for screen in NSScreen.screens {
            let window = AreaOverlayWindow(screen: screen)
            window.selectionDelegate = self
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }

        let initial = preset ?? AreaSelectionMemory.load()

        if let initial,
           let match = overlayWindows.first(where: { $0.screen?.displayID == initial.displayID }),
           match.restoreSelection(sourceRect: initial.sourceRect)
        {
            activeScreenID = initial.displayID
            for other in overlayWindows where other !== match {
                other.clearSelection()
            }
            match.makeKeyAndOrderFront(nil)
        } else if let preferred = overlayWindows.first(where: { $0.screen?.displayID == preset?.displayID })
            ?? overlayWindows.first(where: { $0.screen == NSScreen.main })
            ?? overlayWindows.first
        {
            activeScreenID = preferred.screen?.displayID
            preferred.activateDefaultSelection()
            preferred.makeKeyAndOrderFront(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        publishSelection()

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.cancel()
                return nil
            }
            return event
        }
    }

    func hide() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        activeScreenID = nil
        onSelectionChanged = nil
        onCancel = nil
    }

    private func cancel() {
        let cancel = onCancel
        hide()
        cancel?()
    }

    private func currentResult() -> AreaSelectionResult? {
        let window = overlayWindows.first(where: { $0.screen?.displayID == activeScreenID })
            ?? overlayWindows.first
        return window?.makeResult()
    }

    private func publishSelection() {
        let result = currentResult()
        if let result {
            AreaSelectionMemory.save(result)
        }
        onSelectionChanged?(result)
    }
}

extension AreaSelectionController: AreaOverlaySelectionDelegate {
    func areaOverlayDidBeginEditing(_ window: AreaOverlayWindow) {
        activeScreenID = window.screen?.displayID
        for other in overlayWindows where other !== window {
            other.clearSelection()
        }
        publishSelection()
    }

    func areaOverlayDidChangeSelection(_ window: AreaOverlayWindow) {
        activeScreenID = window.screen?.displayID
        publishSelection()
    }
}
