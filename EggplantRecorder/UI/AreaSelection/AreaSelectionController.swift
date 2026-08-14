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

    /// Space reserved at the bottom so handles stay above the options panel (~186 + 16pt).
    static let optionsReserveHeight: CGFloat = 220

    var isVisible: Bool { !overlayWindows.isEmpty }

    func show(
        onSelectionChanged: @escaping (AreaSelectionResult?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        hide()
        self.onSelectionChanged = onSelectionChanged
        self.onCancel = onCancel

        let remembered = AreaSelectionMemory.load()

        for screen in NSScreen.screens {
            let window = AreaOverlayWindow(screen: screen)
            window.selectionDelegate = self
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }

        if let remembered,
           let match = overlayWindows.first(where: { $0.screen?.displayID == remembered.displayID }),
           match.restoreSelection(sourceRect: remembered.sourceRect)
        {
            activeScreenID = remembered.displayID
            for other in overlayWindows where other !== match {
                other.clearSelection()
            }
            match.makeKeyAndOrderFront(nil)
        } else if let main = overlayWindows.first(where: { $0.screen == NSScreen.main })
            ?? overlayWindows.first
        {
            activeScreenID = main.screen?.displayID
            main.activateDefaultSelection()
            main.makeKeyAndOrderFront(nil)
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
