import AppKit
import SwiftUI

/// Full-screen-centered countdown before capture starts. Esc cancels.
@MainActor
final class CountdownController {
    private var panel: NSPanel?
    private var hosting: NSHostingView<CountdownView>?
    private var model = CountdownModel()
    private var timer: Timer?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var escapeMonitor: Any?

    var isRunning: Bool { continuation != nil }

    /// Returns `true` when the countdown finished, `false` if cancelled.
    func run(seconds: Int, on screen: NSScreen?) async -> Bool {
        cancel()
        guard seconds > 0 else { return true }
        model.remaining = seconds
        show(on: screen ?? NSScreen.main ?? NSScreen.screens.first)
        installEscape()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            startTimer()
        }
    }

    func cancel() {
        finish(proceed: false)
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard continuation != nil else { return }
        if model.remaining <= 1 {
            finish(proceed: true)
            return
        }
        model.remaining -= 1
        if let hosting {
            hosting.rootView = CountdownView(model: model)
        }
    }

    private func finish(proceed: Bool) {
        timer?.invalidate()
        timer = nil
        removeEscape()
        hidePanel()
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: proceed)
    }

    private func show(on screen: NSScreen?) {
        let root = CountdownView(model: model)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 160, height: 176)
        self.hosting = hosting

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 5)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
        self.panel = panel

        position(panel, on: screen)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func position(_ panel: NSPanel, on screen: NSScreen?) {
        guard let screen else { return }
        let size = panel.frame.size
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.midY - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func hidePanel() {
        guard let panel else { return }
        panel.orderOut(nil)
        self.panel = nil
        hosting = nil
    }

    private func installEscape() {
        removeEscape()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancel()
                return nil
            }
            return event
        }
    }

    private func removeEscape() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }
}

@MainActor
final class CountdownModel: ObservableObject {
    @Published var remaining: Int = 3
}

struct CountdownView: View {
    @ObservedObject var model: CountdownModel

    private let fill = Color(red: 0.173, green: 0.180, blue: 0.200)

    var body: some View {
        VStack(spacing: 10) {
            Text("\(model.remaining)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(width: 120, height: 120)
                .background(
                    Circle()
                        .fill(fill.opacity(0.94))
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                )
                .id(model.remaining)
                .transition(.opacity)

            Text("Esc to cancel")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(width: 160, height: 176)
        .animation(.easeInOut(duration: 0.12), value: model.remaining)
        .preferredColorScheme(.dark)
    }
}
