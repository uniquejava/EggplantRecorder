import AppKit
import AVFoundation
import Foundation

@MainActor
final class EditorModel: ObservableObject {
    let path: String
    let name: String
    let player: AVPlayer

    @Published var duration: TimeInterval = 0
    @Published var trimStart: TimeInterval = 0
    @Published var trimEnd: TimeInterval = 0
    @Published var currentTime: TimeInterval = 0
    @Published var isPlaying = false
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var filmstrip: [NSImage] = []
    @Published var loadFailed = false
    @Published var alertMessage: String?

    var onExported: ((String) -> Void)?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var exportTask: Task<Void, Never>?

    static let minimumTrim: TimeInterval = 0.1

    init(path: String, name: String) {
        self.path = path
        self.name = name
        let url = URL(fileURLWithPath: path)
        let player = AVPlayer(playerItem: AVPlayerItem(url: url))
        player.actionAtItemEnd = .pause
        self.player = player
        installObservers()
        Task { await loadMedia(url: url) }
    }

    func teardown() {
        exportTask?.cancel()
        exportTask = nil
        player.pause()
        isPlaying = false
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.replaceCurrentItem(with: nil)
    }

    func togglePlay() {
        if isPlaying {
            pause()
            return
        }
        play()
    }

    func play() {
        guard duration > 0, !isExporting else { return }
        if currentTime >= trimEnd - 0.05 {
            seek(to: trimStart)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to seconds: TimeInterval) {
        let clamped = min(max(seconds, trimStart), max(trimStart, trimEnd))
        currentTime = clamped
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skip(_ delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    func setTrimStart(_ seconds: TimeInterval) {
        if isPlaying { pause() }
        let maxStart = max(0, trimEnd - Self.minimumTrim)
        trimStart = min(max(0, seconds), maxStart)
        if currentTime < trimStart {
            seek(to: trimStart)
        }
    }

    func setTrimEnd(_ seconds: TimeInterval) {
        if isPlaying { pause() }
        let minEnd = min(duration, trimStart + Self.minimumTrim)
        trimEnd = max(min(duration, seconds), minEnd)
        if currentTime > trimEnd {
            seek(to: trimEnd)
        }
    }

    func resetTrim() {
        pause()
        trimStart = 0
        trimEnd = duration
        seek(to: 0)
    }

    var isTrimmed: Bool {
        trimStart > 0.04 || trimEnd < duration - 0.04
    }

    var trimDuration: TimeInterval {
        max(0, trimEnd - trimStart)
    }

    func export() {
        guard !isExporting, duration > 0 else { return }
        exportTask?.cancel()
        exportTask = Task { await performExport() }
    }

    private func performExport() async {
        isExporting = true
        exportProgress = 0
        pause()
        defer {
            isExporting = false
            exportProgress = 0
            exportTask = nil
        }
        do {
            let destination = try RecordingsLibrary.makeEditOutputURL(from: path)
            try await ExportService.exportTrimmed(
                source: URL(fileURLWithPath: path),
                start: trimStart,
                end: trimEnd,
                destination: destination
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.exportProgress = progress
                }
            }
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: destination)
                return
            }
            onExported?(destination.path)
        } catch is CancellationError {
            return
        } catch let error as ExportError {
            if case .cancelled = error { return }
            alertMessage = error.localizedDescription
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

// MARK: - Observers / load

extension EditorModel {
    private func installObservers() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            Task { @MainActor in
                self?.handlePlaybackTime(seconds)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pause()
                self?.seek(to: self?.trimStart ?? 0)
            }
        }
    }

    private func loadMedia(url: URL) async {
        let seconds = await MediaProbe.duration(of: url)
        guard seconds > 0 else {
            loadFailed = true
            return
        }
        duration = seconds
        trimEnd = seconds
        filmstrip = await MediaProbe.filmstrip(of: url, duration: seconds)
    }

    private func handlePlaybackTime(_ seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        currentTime = seconds
        if isPlaying, seconds >= trimEnd - 0.03 {
            pause()
            seek(to: trimEnd)
        }
    }
}
