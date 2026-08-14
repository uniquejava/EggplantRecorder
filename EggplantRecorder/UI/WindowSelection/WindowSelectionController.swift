import AppKit

struct WindowSelectionResult {
    let hit: WindowHit
}

/// Hover windows with a blue dashed border; click to confirm (EggplantShot-style pick).
@MainActor
final class WindowSelectionController {
    private var panels: [WindowPickPanel] = []
    private var eventMonitors: [Any] = []
    private var hitTester = WindowHitTester.snapshot()
    private var hovered: WindowHit?
    private var onComplete: ((WindowSelectionResult) -> Void)?
    private var onCancel: (() -> Void)?
    private(set) var isActive = false

    func show(
        onComplete: @escaping (WindowSelectionResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        hide()
        self.onComplete = onComplete
        self.onCancel = onCancel
        isActive = true
        hitTester = WindowHitTester.snapshot()
        for screen in NSScreen.screens {
            let panel = WindowPickPanel(screen: screen)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        let mouse = NSEvent.mouseLocation
        if let panel = panels.first(where: { NSMouseInRect(mouse, $0.screenFrame, false) }) ?? panels.first {
            panel.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        installMonitors()
        updateHover(at: mouse)
    }

    func hide() {
        removeMonitors()
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        hovered = nil
        isActive = false
        NSCursor.arrow.set()
    }

    private func installMonitors() {
        removeMonitors()
        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .mouseMoved, .leftMouseDragged]
        if let mon = NSEvent.addLocalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            self?.handleMouse(event)
            return nil
        }) {
            eventMonitors.append(mon)
        }
        if let mon = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            self?.handleMouse(event)
        }) {
            eventMonitors.append(mon)
        }
        if let mon = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc
                self.cancel()
                return nil
            }
            return event
        }) {
            eventMonitors.append(mon)
        }
    }

    private func removeMonitors() {
        for mon in eventMonitors {
            NSEvent.removeMonitor(mon)
        }
        eventMonitors.removeAll()
    }

    private func handleMouse(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        switch event.type {
        case .mouseMoved, .leftMouseDragged:
            updateHover(at: point)
        case .leftMouseDown:
            confirmIfPossible(at: point)
        default:
            break
        }
    }

    private func updateHover(at point: CGPoint) {
        let hit = hitTester.hit(at: point)
        hovered = hit
        for panel in panels {
            panel.setHighlight(hit?.frame)
        }
        if hit != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func confirmIfPossible(at point: CGPoint) {
        guard let hit = hovered ?? hitTester.hit(at: point), hit.frame.contains(point) else {
            return
        }
        let result = WindowSelectionResult(hit: hit)
        let complete = onComplete
        hide()
        complete?(result)
    }

    private func cancel() {
        let cancel = onCancel
        hide()
        cancel?()
    }
}
