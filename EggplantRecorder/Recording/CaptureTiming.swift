import CoreMedia
import Foundation

enum CaptureTiming {
    static func relativePTS(host pts: CMTime, sessionAnchor: CMTime, pausedAccumulated: CMTime) -> CMTime {
        var relative = CMTimeSubtract(pts, sessionAnchor)
        if CMTimeCompare(pausedAccumulated, .zero) > 0 {
            relative = CMTimeSubtract(relative, pausedAccumulated)
        }
        if CMTimeCompare(relative, .zero) < 0 {
            relative = .zero
        }
        return relative
    }

    static func monotonicPTS(_ candidate: CMTime, previous: CMTime) -> CMTime {
        guard previous.isValid else { return candidate }
        if CMTimeCompare(candidate, previous) <= 0 {
            return CMTimeAdd(previous, CMTime(value: 1, timescale: 600))
        }
        return candidate
    }
}
