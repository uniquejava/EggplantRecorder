import Foundation

struct RecordingMediaInfo: Sendable, Equatable {
    var width: Int
    var height: Int
    var frameRate: Double
    var audioTrackCount: Int
    var fileSize: Int64

    var sizeLabel: String { "\(width)×\(height)" }

    var frameRateLabel: String {
        "\(displayFPS) FPS"
    }

    var displayFPS: Int {
        max(1, Int(frameRate.rounded()))
    }
}

struct ExportSettings: Equatable, Sendable {
    enum FrameRate: String, CaseIterable, Identifiable, Sendable {
        case original
        case fps30
        case fps24
        case fps15

        var id: String { rawValue }

        var cap: Double? {
            switch self {
            case .original: nil
            case .fps30: 30
            case .fps24: 24
            case .fps15: 15
            }
        }
    }

    enum Resolution: String, CaseIterable, Identifiable, Sendable {
        case original
        case p1080
        case p720

        var id: String { rawValue }

        var maxHeight: Int? {
            switch self {
            case .original: nil
            case .p1080: 1080
            case .p720: 720
            }
        }
    }

    enum Quality: String, CaseIterable, Identifiable, Sendable {
        case high
        case medium
        case low

        var id: String { rawValue }

        var title: String {
            switch self {
            case .high: "High"
            case .medium: "Medium"
            case .low: "Low"
            }
        }

        var bitrateFactor: Int {
            switch self {
            case .high: 6
            case .medium: 3
            case .low: 1
            }
        }
    }

    enum AudioChannels: String, CaseIterable, Identifiable, Sendable {
        case stereo
        case mono

        var id: String { rawValue }

        var title: String {
            switch self {
            case .stereo: "Stereo"
            case .mono: "Mono"
            }
        }

        var channelCount: Int {
            switch self {
            case .stereo: 2
            case .mono: 1
            }
        }
    }

    var frameRate: FrameRate = .original
    var resolution: Resolution = .original
    var quality: Quality = .high
    var volume: Double = 1
    var audioChannels: AudioChannels = .stereo

    var processesAudio: Bool {
        volume < 0.995 || audioChannels == .mono
    }

    func frameRateTitle(source: RecordingMediaInfo?) -> String {
        switch frameRate {
        case .original:
            if let source {
                return "Original (\(source.frameRateLabel))"
            }
            return "Original"
        case .fps30: return "30 FPS"
        case .fps24: return "24 FPS"
        case .fps15: return "15 FPS"
        }
    }

    func resolutionTitle(source: RecordingMediaInfo?) -> String {
        switch resolution {
        case .original:
            if let source {
                return "Original (\(source.sizeLabel))"
            }
            return "Original"
        case .p1080: return "1080p"
        case .p720: return "720p"
        }
    }

    func availableFrameRates(source: RecordingMediaInfo?) -> [FrameRate] {
        let fps = source?.frameRate ?? 30
        return FrameRate.allCases.filter { pick in
            guard let cap = pick.cap else { return true }
            return fps > cap + 0.5
        }
    }

    func availableResolutions(source: RecordingMediaInfo?) -> [Resolution] {
        let height = source?.height ?? 1080
        return Resolution.allCases.filter { pick in
            guard let maxH = pick.maxHeight else { return true }
            return height > maxH
        }
    }

    func outputSize(sourceWidth: Int, sourceHeight: Int) -> (Int, Int) {
        guard let maxH = resolution.maxHeight, sourceHeight > maxH, sourceHeight > 0 else {
            return even(sourceWidth, sourceHeight)
        }
        let scale = Double(maxH) / Double(sourceHeight)
        let width = Int((Double(sourceWidth) * scale).rounded())
        return even(width, maxH)
    }

    func targetFrameRate(sourceFPS: Double) -> Double? {
        guard let cap = frameRate.cap, sourceFPS > cap + 0.5 else { return nil }
        return cap
    }

    func videoBitrate(width: Int, height: Int, sourceFPS: Double) -> Int {
        let base = max(width * height * quality.bitrateFactor, 400_000)
        let source = max(sourceFPS, 1)
        let outFPS = targetFrameRate(sourceFPS: source) ?? source
        let scale = min(max(outFPS / source, 0.25), 1)
        return max(Int((Double(base) * scale).rounded()), 250_000)
    }

    func estimatedBytes(
        trimDuration: TimeInterval,
        fullDuration: TimeInterval,
        source: RecordingMediaInfo
    ) -> Int64 {
        guard source.fileSize > 0 else { return 0 }
        let timeScale = max(trimDuration, 0) / max(fullDuration, 0.001)
        let (outWidth, outHeight) = outputSize(sourceWidth: source.width, sourceHeight: source.height)
        let pixelScale = Double(outWidth * outHeight) / Double(max(source.width * source.height, 1))
        let sourceFPS = max(source.frameRate, 1)
        let outFPS = targetFrameRate(sourceFPS: sourceFPS) ?? sourceFPS
        let fpsScale = min(max(outFPS / sourceFPS, 0.25), 1)
        let qualityScale: Double
        switch quality {
        case .high: qualityScale = 0.9
        case .medium: qualityScale = 0.45
        case .low: qualityScale = 0.18
        }
        let audioScale = audioChannels == .mono ? 0.96 : 1
        let bytes = Double(source.fileSize) * timeScale * pixelScale * fpsScale * qualityScale * audioScale
        return Int64(max(bytes.rounded(), 50_000))
    }

    func estimatedSizeText(
        trimDuration: TimeInterval,
        fullDuration: TimeInterval,
        source: RecordingMediaInfo?
    ) -> String {
        guard let source, trimDuration > 0 else { return "About —" }
        let bytes = estimatedBytes(
            trimDuration: trimDuration,
            fullDuration: fullDuration,
            source: source
        )
        let value = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return "About \(value)"
    }

    private func even(_ width: Int, _ height: Int) -> (Int, Int) {
        var w = max(width, 2)
        var h = max(height, 2)
        if w % 2 != 0 { w -= 1 }
        if h % 2 != 0 { h -= 1 }
        return (max(w, 2), max(h, 2))
    }
}
