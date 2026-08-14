import AppKit
import Combine
import Foundation

enum AppPhase {
    case idle
    case configuring
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
    let areaRecordingChrome = AreaRecordingChromeController()
    let windowSelection = WindowSelectionController()

    /// Set while configuring area; consumed when OptionsBar records.
    private(set) var pendingArea: AreaSelectionResult?
    /// Set after window pick; consumed when OptionsBar records.
    private(set) var pendingWindow: WindowSelectionResult?

    /// Kept while recording so area chrome / restart can reuse the same rect + settings.
    private var activeRecordingConfig: RecordingConfig?
    private var activeArea: AreaSelectionResult?

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
        areaRecordingChrome.configure(appState: self)
        Task { await refreshRecordings() }
    }

    func showOptions(mode: RecordingKind, anchorRect: CGRect? = nil) {
        guard phase != .recording else { return }
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

    func showAreaSelection() {
        guard phase != .recording else { return }
        optionsBar.hide()
        windowSelection.hide()
        pendingArea = nil
        pendingWindow = nil
        phase = .configuring
        optionsMode = .area
        areaSelection.show(
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
        guard phase != .recording else { return }
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

    func hideOptions() {
        optionsBar.hide()
        areaSelection.hide()
        if phase == .configuring {
            phase = .idle
            pendingArea = nil
            pendingWindow = nil
        }
    }

    func startRecording(config: RecordingConfig) async {
        lastErrorMessage = nil
        do {
            try RecordingsLibrary.ensureDirectory()
            let output = RecordingsLibrary.makeOutputURL(kind: config.kind)
            // Capture area before clearing pending — needed for in-recording chrome.
            let areaForChrome: AreaSelectionResult? = {
                if config.kind == .area {
                    if let pending = pendingArea { return pending }
                    if let active = activeArea { return active }
                    if let rect = config.areaSourceRect,
                       let displayID = Self.displayID(from: config.sourceID),
                       let w = config.areaPixelWidth,
                       let h = config.areaPixelHeight
                    {
                        return AreaSelectionResult(
                            displayID: displayID,
                            sourceRect: rect,
                            pixelWidth: w,
                            pixelHeight: h
                        )
                    }
                }
                return nil
            }()
            try await recorder.start(config: config, outputURL: output)
            activeRecordingConfig = config
            activeArea = areaForChrome
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
            if let areaForChrome {
                areaRecordingChrome.show(area: areaForChrome)
            } else {
                areaRecordingChrome.hide()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            optionsBar.showError(error.localizedDescription)
        }
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
        areaRecordingChrome.reload()
    }

    func stopRecording() async {
        guard phase == .recording else { return }
        stopElapsedTimer()
        areaRecordingChrome.hide()
        do {
            let path = try await recorder.stop()
            phase = .idle
            isPaused = false
            activeRecordingConfig = nil
            activeArea = nil
            statusItem.enterIdleMode()
            highlightPath = path
            await refreshRecordings()
            filesList.show(highlightPath: path)
        } catch {
            phase = .idle
            isPaused = false
            activeRecordingConfig = nil
            activeArea = nil
            statusItem.enterIdleMode()
            lastErrorMessage = error.localizedDescription
            presentAlert(title: "Recording failed", message: error.localizedDescription)
        }
    }

    /// Discard the in-progress recording (delete file, no Files List).
    func cancelRecording() async {
        guard phase == .recording else { return }
        stopElapsedTimer()
        areaRecordingChrome.hide()
        do {
            let path = try await recorder.stop()
            try? FileManager.default.removeItem(atPath: path)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        phase = .idle
        isPaused = false
        activeRecordingConfig = nil
        activeArea = nil
        statusItem.enterIdleMode()
    }

    /// Discard current take and start again with the same settings / area.
    func restartRecording() async {
        guard phase == .recording, let config = activeRecordingConfig else { return }
        stopElapsedTimer()
        areaRecordingChrome.hide()
        do {
            let path = try await recorder.stop()
            try? FileManager.default.removeItem(atPath: path)
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .idle
            isPaused = false
            activeRecordingConfig = nil
            activeArea = nil
            statusItem.enterIdleMode()
            return
        }
        phase = .idle
        isPaused = false
        statusItem.enterIdleMode()
        await startRecording(config: config)
    }

    func showFilesList() {
        Task {
            await refreshRecordings()
            filesList.show(highlightPath: highlightPath)
        }
    }

    func refreshRecordings() async {
        recordings = await RecordingsLibrary.list()
    }

    func quit() {
        if phase == .recording {
            Task {
                areaRecordingChrome.hide()
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
        areaRecordingChrome.reload()
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
}
