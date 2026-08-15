import CoreMedia
import XCTest

@testable import EggplantRecorder

/// Pause/resume PTS math. A regression here doesn't crash — it silently produces a recording
/// whose timeline is stretched, frozen, or out of order, which is why it's worth pinning.
final class CaptureTimingTests: XCTestCase {
    private let scale: CMTimeScale = 600

    private func time(_ seconds: Double) -> CMTime {
        CMTime(value: CMTimeValue(seconds * Double(scale)), timescale: scale)
    }

    private func seconds(_ time: CMTime) -> Double {
        CMTimeGetSeconds(time)
    }

    // MARK: relativePTS

    func testSubtractsTheSessionAnchor() {
        let relative = CaptureTiming.relativePTS(
            host: time(10),
            sessionAnchor: time(4),
            pausedAccumulated: .zero
        )
        XCTAssertEqual(seconds(relative), 6, accuracy: 1e-9)
    }

    func testPausedTimeCompressesTheTimeline() {
        // 10 s of wall clock with 2 s paused must land at 8 s − 4 s anchor = 4 s of media.
        let relative = CaptureTiming.relativePTS(
            host: time(10),
            sessionAnchor: time(4),
            pausedAccumulated: time(2)
        )
        XCTAssertEqual(seconds(relative), 4, accuracy: 1e-9)
    }

    func testNegativeRelativeTimeClampsToZero() {
        // A sample stamped before the anchor (first frame races the anchor assignment).
        let relative = CaptureTiming.relativePTS(
            host: time(3),
            sessionAnchor: time(4),
            pausedAccumulated: .zero
        )
        XCTAssertEqual(relative, .zero)
    }

    func testPausedLongerThanElapsedAlsoClampsToZero() {
        let relative = CaptureTiming.relativePTS(
            host: time(10),
            sessionAnchor: time(4),
            pausedAccumulated: time(99)
        )
        XCTAssertEqual(relative, .zero)
    }

    func testZeroPausedAccumulatedIsNotSubtracted() {
        let relative = CaptureTiming.relativePTS(
            host: time(5),
            sessionAnchor: .zero,
            pausedAccumulated: .zero
        )
        XCTAssertEqual(seconds(relative), 5, accuracy: 1e-9)
    }

    // MARK: monotonicPTS

    func testFirstSamplePassesThroughWhenPreviousIsInvalid() {
        let candidate = time(7)
        XCTAssertEqual(CaptureTiming.monotonicPTS(candidate, previous: .invalid), candidate)
    }

    func testIncreasingCandidateIsUsedAsIs() {
        let candidate = time(8)
        XCTAssertEqual(CaptureTiming.monotonicPTS(candidate, previous: time(7)), candidate)
    }

    func testEqualCandidateIsBumpedByOneTick() {
        let previous = time(7)
        let result = CaptureTiming.monotonicPTS(previous, previous: previous)
        XCTAssertEqual(result, CMTimeAdd(previous, CMTime(value: 1, timescale: 600)))
        XCTAssertGreaterThan(CMTimeCompare(result, previous), 0)
    }

    func testGoingBackwardsIsBumpedForwardFromPrevious() {
        // Resume can hand back a PTS behind the last written one; the writer must never see it.
        let previous = time(7)
        let result = CaptureTiming.monotonicPTS(time(6), previous: previous)
        XCTAssertEqual(result, CMTimeAdd(previous, CMTime(value: 1, timescale: 600)))
        XCTAssertGreaterThan(CMTimeCompare(result, previous), 0)
    }

    func testRepeatedIdenticalSamplesKeepAdvancing() {
        let stuck = time(7)
        var previous = stuck
        for _ in 0..<5 {
            let next = CaptureTiming.monotonicPTS(stuck, previous: previous)
            XCTAssertGreaterThan(CMTimeCompare(next, previous), 0)
            previous = next
        }
    }
}
