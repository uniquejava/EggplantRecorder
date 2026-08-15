import AppKit
import Combine
import Foundation

enum AppPhase {
    case idle
    case configuring
    case countdown
    case recording
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: AppPhase = .idle
    @Published var isPaused = false
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var optionsMode: RecordingKind = .screen
    @Published var lastErrorMessage: String?
    @Published var highlightPath: String?
    @Published var recordings: [RecordingEntry] = []

    let recorder = RecorderController()
    let optionsBar = OptionsBarController()
    let filesList = FilesListController()
    let statusItem = StatusItemController()
    let areaSelection = AreaSelectionController()
    let recordingChrome = RecordingChromeController()
    let windowSelection = WindowSelectionController()
    let editor = EditorController()
    let countdown = CountdownController()

    /// Set while configuring area; consumed when OptionsBar records.
    private(set) var pendingArea: AreaSelectionResult?
    /// Set after window pick; consumed when OptionsBar records.
    private(set) var pendingWindow: WindowSelectionResult?

    /// Kept while recording so recording chrome / restart can reuse the same target + settings.
    private var activeRecordingConfig: RecordingConfig?
    private var activeArea: AreaSelectionResult?
    private var activeWindow: WindowHit?

    private var elapsedTimer: Timer?
    private var recordingAnchor = Date()
    private var pausedAccumulated: TimeInterval = 0
    private var pauseBeganAt: Date?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        recorder.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func bootstrap() {
        statusItem.install(appState: self)
        optionsBar.configure(appState: self)
        filesList.configure(appState: self)
        editor.configure(appState: self)
        recordingChrome.configure(appState: self)
        Task { await refreshRecordings() }
    }

    func showOptions(mode: RecordingKind, anchorRect: CGRect? = nil) {
        guard phase != .recording, phase != .countdown else { return }
        // Area keeps its dim overlay while the options panel is up (OMI-like).
        if mode != .area {
            areaSelection.hide()
            pendingArea = nil
        }
        windowSelection.hide()
        optionsMode = mode
        phase = .configuring
        optionsBar.show(mode: mode, anchorRect: anchorRect)
    }

    func showAreaSelection(preset: (displayID: CGDirectDisplayID, sourceRect: CGRect)? = nil) {
        guard phase != .recording, phase != .countdown else { return }
        optionsBar.hide()
        windowSelection.hide()
        pendingArea = nil
        pendingWindow = nil
        phase = .configuring
        optionsMode = .area
        areaSelection.show(
            preset: preset,
            onSelectionChanged: { [weak self] result in
                guard let self else { return }
                self.pendingArea = result
                self.optionsBar.noteAreaSelectionChanged()
            },
            onCancel: { [weak self] in
                guard let self else { return }
                self.pendingArea = nil
                self.optionsBar.hide()
                self.phase = .idle
            }
        )
        // Same options panel as Screen / Window — shown alongside the selection.
        optionsBar.show(mode: .area)
    }

    func showWindowSelection() {
        guard phase != .recording, phase != .countdown else { return }
        optionsBar.hide()
        areaSelection.hide()
        pendingArea = nil
        pendingWindow = nil
        phase = .configuring
        windowSelection.show(
            onComplete: { [weak self] result in
                guard let self else { return }
                self.pendingWindow = result
                self.showOptions(mode: .window, anchorRect: result.hit.frame)
            },
            onCancel: { [weak self] in
                guard let self else { return }
                self.pendingWindow = nil
                self.phase = .idle
            }
        )
    }

    /// Hover-pick a window, then continue as Area with that window’s frame as the selection.
    func showWindowAreaSelection() {
        guard phase != .recording, phase != .countdown else { return }
        optionsBar.hide()
        areaSelection.hide()
        pendingArea = nil
        pendingWindow = nil
        phase = .configuring
        windowSelection.show(
            onComplete: { [weak self] result in
                guard let self else { return }
                guard let preset = AreaSelectionResult.presetFromWindowFrame(result.hit.frame) else {
                    self.lastErrorMessage = "Could not use that window as an area."
                    self.phase = .idle
                    return
                }
                self.showAreaSelection(preset: preset)
            },
            onCancel: { [weak self] in
                guard let self else { return }
                self.phase = .idle
            }
        )
    }

    func hideOptions() {
        if phase == .countdown {
            countdown.cancel()
            return
        }
        optionsBar.hide()
        areaSelection.hide()
        if phase == .configuring {
            phase = .idle
            pendingArea = nil
            pendingWindow = nil
        }
    }

    func startRecording(config: RecordingConfig, skipCountdown: Bool = false) async {
        lastErrorMessage = nil
        if !skipCountdown, config.countdown != .none {
            let proceeded = await runCountdown(for: config)
            guard proceeded else { return }
        }
        do {
            try RecordingsLibrary.ensureDirectory()
            let output = RecordingsLibrary.makeOutputURL(kind: config.kind)
            // Resolve the chrome target before clearing pending — needed for in-recording chrome.
            let chromeTarget = chromeTarget(for: config)
            try await recorder.start(config: config, outputURL: output)
            activeRecordingConfig = config
            switch chromeTarget {
            case .area(let area):
                activeArea = area
                activeWindow = nil
            case .window(let hit):
                activeArea = nil
                activeWindow = hit
            case nil:
                activeArea = nil
                activeWindow = nil
            }
            pendingArea = nil
            pendingWindow = nil
            areaSelection.hide()
            optionsBar.hide()
            phase = .recording
            isPaused = false
            elapsedSeconds = 0
            recordingAnchor = Date()
            pausedAccumulated = 0
            pauseBeganAt = nil
            startElapsedTimer()
            statusItem.enterRecordingMode()
            if let chromeTarget {
                recordingChrome.show(target: chromeTarget)
            } else {
                recordingChrome.hide()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .configuring
            areaSelection.setSelectionLocked(false)
            optionsBar.showError(error.localizedDescription)
        }
    }

    /// Area and Window recordings get a dashed capture frame + mini control bar; full-screen doesn't.
    /// Falls back to the config so Restart (which has no pending selection) still gets its chrome.
    private func chromeTarget(for config: RecordingConfig) -> RecordingChromeTarget? {
        switch config.kind {
        case .screen:
            return nil
        case .area:
            if let area = pendingArea ?? activeArea { return .area(area) }
            guard let rect = config.areaSourceRect,
                  let displayID = Self.displayID(from: config.sourceID),
                  let width = config.areaPixelWidth,
                  let height = config.areaPixelHeight
            else { return nil }
            return .area(
                AreaSelectionResult(
                    displayID: displayID,
                    sourceRect: rect,
                    pixelWidth: width,
                    pixelHeight: height
                )
            )
        case .window:
            if let hit = pendingWindow?.hit ?? activeWindow { return .window(hit) }
            guard let windowID = Self.windowID(from: config.sourceID),
                  let frame = WindowHitTester.liveFrame(of: windowID)
            else { return nil }
            return .window(WindowHit(windowID: windowID, frame: frame, title: "", ownerName: ""))
        }
    }

    /// Hide options, show the number overlay, Esc cancels back to the options bar.
    private func runCountdown(for config: RecordingConfig) async -> Bool {
        optionsBar.hide()
        areaSelection.setSelectionLocked(true)
        areaSelection.isEscapeEnabled = false
        phase = .countdown
        let screen = countdownScreen(for: config)
        let proceeded = await countdown.run(seconds: config.countdown.rawValue, on: screen)
        areaSelection.setSelectionLocked(false)
        areaSelection.isEscapeEnabled = true
        if proceeded {
            return true
        }
        phase = .configuring
        optionsBar.show(mode: config.kind)
        return false
    }

    private func countdownScreen(for config: RecordingConfig) -> NSScreen? {
        if config.kind == .area, let area = pendingArea {
            return NSScreen.screens.first(where: { $0.displayID == area.displayID })
        }
        if config.kind == .window, let hit = pendingWindow?.hit {
            return NSScreen.screens.first(where: { $0.frame.intersects(hit.frame) })
        }
        if let displayID = Self.displayID(from: config.sourceID) {
            return NSScreen.screens.first(where: { $0.displayID == displayID })
        }
        return NSScreen.main
    }

    func togglePause() {
        guard phase == .recording else { return }
        if isPaused {
            recorder.resume()
            if let began = pauseBeganAt {
                pausedAccumulated += Date().timeIntervalSince(began)
            }
            pauseBeganAt = nil
            isPaused = false
        } else {
            recorder.pause()
            pauseBeganAt = Date()
            isPaused = true
        }
        statusItem.refreshRecordingControls()
        recordingChrome.reload()
    }

    func stopRecording() async {
        guard phase == .recording else { return }
        stopElapsedTimer()
        recordingChrome.hide()
        do {
            let path = try await recorder.stop()
            returnToIdle()
            highlightPath = path
            await refreshRecordings()
            if AppPreferences.shared.openFilesListAfterRecording {
                filesList.show(highlightPath: path)
            }
        } catch {
            returnToIdle()
            lastErrorMessage = error.localizedDescription
            presentAlert(title: "Recording failed", message: error.localizedDescription)
        }
    }

    /// Discard the in-progress recording (delete file, no Files List).
    func cancelRecording() async {
        guard phase == .recording else { return }
        stopElapsedTimer()
        recordingChrome.hide()
        do {
            let path = try await recorder.stop()
            try? FileManager.default.removeItem(atPath: path)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        returnToIdle()
    }

    /// Discard current take and start again with the same settings / area or window.
    func restartRecording() async {
        guard phase == .recording, let config = activeRecordingConfig else { return }
        stopElapsedTimer()
        recordingChrome.hide()
        do {
            let path = try await recorder.stop()
            try? FileManager.default.removeItem(atPath: path)
        } catch {
            lastErrorMessage = error.localizedDescription
            returnToIdle()
            return
        }
        // Keep the active target — startRecording reuses it for the next take's chrome.
        returnToIdle(keepActiveTarget: true)
        await startRecording(config: config, skipCountdown: true)
    }

    /// Shared teardown after a take ends.
    private func returnToIdle(keepActiveTarget: Bool = false) {
        phase = .idle
        isPaused = false
        if !keepActiveTarget {
            activeRecordingConfig = nil
            activeArea = nil
            activeWindow = nil
        }
        statusItem.enterIdleMode()
    }

    func showFilesList() {
        Task {
            await refreshRecordings()
            filesList.show(highlightPath: highlightPath)
        }
    }

    func openPreferences() {
        if let open = OpenSettingsGateway.shared.open {
            open()
            AppActivation.preferForeground()
        } else {
            NotificationCenter.default.post(name: .openAppPreferences, object: nil)
        }
    }

    func showEditor(_ entry: RecordingEntry) {
        editor.show(entry: entry)
    }

    func refreshRecordings() async {
        recordings = await RecordingsLibrary.list()
    }

    func quit() {
        if phase == .countdown {
            countdown.cancel()
        }
        if phase == .recording {
            Task {
                recordingChrome.hide()
                _ = try? await recorder.stop()
                NSApp.terminate(nil)
            }
        } else {
            NSApp.terminate(nil)
        }
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickElapsed()
            }
        }
        if let elapsedTimer {
            RunLoop.main.add(elapsedTimer, forMode: .common)
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func tickElapsed() {
        guard phase == .recording, !isPaused else { return }
        let wall = Date().timeIntervalSince(recordingAnchor) - pausedAccumulated
        elapsedSeconds = max(0, wall)
        statusItem.refreshRecordingControls()
        recordingChrome.reload()
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static func displayID(from sourceID: String) -> CGDirectDisplayID? {
        guard sourceID.hasPrefix("display:") else { return nil }
        guard let value = UInt32(String(sourceID.dropFirst("display:".count))) else { return nil }
        return CGDirectDisplayID(value)
    }

    private static func windowID(from sourceID: String) -> CGWindowID? {
        guard sourceID.hasPrefix("window:") else { return nil }
        guard let value = UInt32(String(sourceID.dropFirst("window:".count))) else { return nil }
        return CGWindowID(value)
    }
}
