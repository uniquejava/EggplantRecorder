import AppKit
import AVFoundation
import Foundation

enum MediaProbe {
    static func duration(of url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite && seconds > 0 ? seconds : 0
        } catch {
            return 0
        }
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    static func formatClock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// First-frame thumbnail for Files List (async; fails soft to nil).
    static func thumbnail(of url: URL, maxSize: CGSize = CGSize(width: 128, height: 72)) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        do {
            let (cgImage, _) = try await generator.image(at: time)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            return nil
        }
    }

    /// Sparse stills for the trim filmstrip (fails soft to []).
    static func filmstrip(
        of url: URL,
        duration: TimeInterval,
        count: Int = 12,
        maxSize: CGSize = CGSize(width: 180, height: 100)
    ) async -> [NSImage] {
        guard duration > 0, count > 0 else { return [] }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

        var images: [NSImage] = []
        images.reserveCapacity(count)
        for i in 0..<count {
            let seconds = duration * (Double(i) + 0.5) / Double(count)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            do {
                let (cgImage, _) = try await generator.image(at: time)
                images.append(
                    NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                )
            } catch {
                continue
            }
        }
        return images
    }
}
