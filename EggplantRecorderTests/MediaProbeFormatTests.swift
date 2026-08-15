import XCTest

@testable import EggplantRecorder

/// The two clock formatters differ in one deliberate way: the live recording clock **truncates**
/// so it never shows a second that hasn't elapsed, while the library duration column **rounds**.
final class MediaProbeFormatTests: XCTestCase {
    func testClockTruncatesRatherThanRounds() {
        XCTAssertEqual(MediaProbe.formatClock(59.9), "00:00:59")
        XCTAssertEqual(MediaProbe.formatClock(0.99), "00:00:00")
    }

    func testDurationRoundsRatherThanTruncates() {
        XCTAssertEqual(MediaProbe.formatDuration(59.9), "01:00")
        XCTAssertEqual(MediaProbe.formatDuration(59.4), "00:59")
    }

    func testClockAlwaysShowsHours() {
        XCTAssertEqual(MediaProbe.formatClock(0), "00:00:00")
        XCTAssertEqual(MediaProbe.formatClock(60), "00:01:00")
        XCTAssertEqual(MediaProbe.formatClock(3600), "01:00:00")
        XCTAssertEqual(MediaProbe.formatClock(3661), "01:01:01")
    }

    func testDurationOnlyShowsHoursWhenNeeded() {
        XCTAssertEqual(MediaProbe.formatDuration(0), "00:00")
        XCTAssertEqual(MediaProbe.formatDuration(90), "01:30")
        XCTAssertEqual(MediaProbe.formatDuration(3599), "59:59")
        XCTAssertEqual(MediaProbe.formatDuration(3600), "01:00:00")
    }

    func testNegativesClampToZero() {
        XCTAssertEqual(MediaProbe.formatClock(-5), "00:00:00")
        XCTAssertEqual(MediaProbe.formatDuration(-5), "00:00")
    }

    func testLongRecordingsRollOverCorrectly() {
        // 10 h 17 m 36 s
        XCTAssertEqual(MediaProbe.formatClock(37056), "10:17:36")
    }
}
