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
    @Published var settings = AppPreferences.shared.defaultExportSettings()
    @Published var sourceInfo: RecordingMediaInfo?
    @Published var previewPlayer: AVPlayer?
    @Published var isPreviewExport = false

    var onExported: ((String) -> Void)?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var exportTask: Task<Void, Never>?
    private var previewURL: URL?
    private var previewEndObserver: NSObjectProtocol?

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
        closePreview()
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
        if previewPlayer != nil {
            togglePreviewPlay()
            return
        }
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

    var estimatedSizeText: String {
        settings.estimatedSizeText(
            trimDuration: trimDuration,
            fullDuration: duration,
            source: sourceInfo
        )
    }

    func export() {
        guard !isExporting, duration > 0 else { return }
        exportTask?.cancel()
        exportTask = Task { await performExport(preview: false) }
    }

    func exportPreview() {
        guard !isExporting, duration > 0 else { return }
        exportTask?.cancel()
        exportTask = Task { await performExport(preview: true) }
    }

    func closePreview() {
        if let previewEndObserver {
            NotificationCenter.default.removeObserver(previewEndObserver)
            self.previewEndObserver = nil
        }
        previewPlayer?.pause()
        previewPlayer?.replaceCurrentItem(with: nil)
        previewPlayer = nil
        if let previewURL {
            try? FileManager.default.removeItem(at: previewURL)
            self.previewURL = nil
        }
    }

    private func togglePreviewPlay() {
        guard let previewPlayer else { return }
        if previewPlayer.rate > 0 {
            previewPlayer.pause()
        } else {
            previewPlayer.play()
        }
    }

    private func performExport(preview: Bool) async {
        isExporting = true
        isPreviewExport = preview
        exportProgress = 0
        pause()
        defer {
            isExporting = false
            isPreviewExport = false
            exportProgress = 0
            exportTask = nil
        }
        do {
            let end = preview ? min(trimEnd, trimStart + TimeInterval(AppPreferences.shared.editPreviewSeconds)) : trimEnd
            let destination = preview
                ? FileManager.default.temporaryDirectory
                    .appendingPathComponent("EggplantRecorder-preview-\(UUID().uuidString).mp4")
                : try RecordingsLibrary.makeEditOutputURL(from: path)
            try await ExportService.exportTrimmed(
                source: URL(fileURLWithPath: path),
                start: trimStart,
                end: end,
                destination: destination,
                settings: settings
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.exportProgress = progress
                }
            }
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: destination)
                return
            }
            if preview {
                presentPreview(url: destination)
            } else {
                onExported?(destination.path)
            }
        } catch is CancellationError {
            return
        } catch let error as ExportError {
            if case .cancelled = error { return }
            alertMessage = error.localizedDescription
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func presentPreview(url: URL) {
        closePreview()
        previewURL = url
        let item = AVPlayerItem(url: url)
        let preview = AVPlayer(playerItem: item)
        preview.volume = Float(settings.volume)
        previewPlayer = preview
        previewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.previewPlayer?.pause()
            }
        }
        preview.play()
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
        if let info = await MediaProbe.mediaInfo(of: url) {
            sourceInfo = info
            if !settings.availableFrameRates(source: info).contains(settings.frameRate) {
                settings.frameRate = .original
            }
            if !settings.availableResolutions(source: info).contains(settings.resolution) {
                settings.resolution = .original
            }
        }
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
