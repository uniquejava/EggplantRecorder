import XCTest

@testable import EggplantRecorder

/// Trim-handle clamping. These are the constraints that stop Export being handed a zero-length or
/// out-of-range range.
///
/// **Every test body here must stay synchronous.** `EditorModel.init` kicks off
/// `Task { await loadMedia(url:) }`, which writes `duration` and `trimEnd`. Because the bodies are
/// `@MainActor` and contain no `await`, that continuation cannot interleave with them — add an
/// `await` and these become flaky.
@MainActor
final class EditorModelTrimTests: XCTestCase {
    private func makeModel(duration: TimeInterval = 30) -> EditorModel {
        // A path that will never load: `loadMedia` fails soft and we set the fields ourselves.
        let model = EditorModel(
            path: NSTemporaryDirectory() + "/EggplantRecorderTests-missing-\(UUID().uuidString).mp4",
            name: "Fixture"
        )
        model.duration = duration
        model.trimStart = 0
        model.trimEnd = duration
        return model
    }

    func testTrimStartCannotCrossTheEnd() {
        let model = makeModel()
        model.setTrimStart(40)
        XCTAssertEqual(model.trimStart, 30 - EditorModel.minimumTrim, accuracy: 1e-9)
        XCTAssertLessThan(model.trimStart, model.trimEnd)
    }

    func testTrimStartCannotGoNegative() {
        let model = makeModel()
        model.setTrimStart(-5)
        XCTAssertEqual(model.trimStart, 0)
    }

    func testTrimEndCannotExceedTheDuration() {
        let model = makeModel()
        model.setTrimEnd(100)
        XCTAssertEqual(model.trimEnd, 30)
    }

    func testTrimEndCannotCollapseOntoTheStart() {
        let model = makeModel()
        model.trimStart = 10
        model.setTrimEnd(10.05)
        XCTAssertEqual(model.trimEnd, 10 + EditorModel.minimumTrim, accuracy: 1e-9)
        XCTAssertGreaterThan(model.trimEnd, model.trimStart)
    }

    func testTrimEndCannotGoNegative() {
        let model = makeModel()
        model.setTrimEnd(-5)
        XCTAssertEqual(model.trimEnd, EditorModel.minimumTrim, accuracy: 1e-9)
    }

    func testTheRangeAlwaysKeepsTheMinimumLength() {
        let model = makeModel()
        for candidate in [-10.0, 0, 5, 29.5, 30, 1000] {
            model.setTrimStart(candidate)
            XCTAssertGreaterThanOrEqual(
                model.trimEnd - model.trimStart,
                EditorModel.minimumTrim - 1e-9,
                "start=\(candidate) collapsed the range"
            )
        }
    }

    func testTrimDurationIsNeverNegative() {
        let model = makeModel()
        model.trimStart = 5
        model.trimEnd = 3
        XCTAssertEqual(model.trimDuration, 0)
    }

    func testTrimDurationIsTheRangeLength() {
        let model = makeModel()
        model.trimStart = 5
        model.trimEnd = 20
        XCTAssertEqual(model.trimDuration, 15, accuracy: 1e-9)
    }

    func testUntrimmedRangeIsNotReportedAsTrimmed() {
        let model = makeModel()
        XCTAssertFalse(model.isTrimmed)
    }

    func testTinyAdjustmentsInsideTheDeadBandAreNotTrimmed() {
        // 0.04 s of slack so a pixel of handle jitter doesn't make Export re-encode.
        let model = makeModel()
        model.trimStart = 0.02
        model.trimEnd = 29.98
        XCTAssertFalse(model.isTrimmed)
    }

    func testRealAdjustmentsAreReportedAsTrimmed() {
        let model = makeModel()
        model.trimStart = 1
        XCTAssertTrue(model.isTrimmed)

        let other = makeModel()
        other.trimEnd = 29
        XCTAssertTrue(other.isTrimmed)
    }

    func testResetRestoresTheFullRange() {
        let model = makeModel()
        model.trimStart = 5
        model.trimEnd = 20
        model.resetTrim()
        XCTAssertEqual(model.trimStart, 0)
        XCTAssertEqual(model.trimEnd, 30)
        XCTAssertFalse(model.isTrimmed)
    }

    func testSeekIsClampedToTheTrimRange() {
        let model = makeModel()
        model.trimStart = 5
        model.trimEnd = 20

        model.seek(to: 0)
        XCTAssertEqual(model.currentTime, 5)

        model.seek(to: 100)
        XCTAssertEqual(model.currentTime, 20)

        model.seek(to: 12)
        XCTAssertEqual(model.currentTime, 12)
    }

    func testMovingTheStartPastTheCursorPullsTheCursorAlong() {
        let model = makeModel()
        model.seek(to: 2)
        model.setTrimStart(10)
        XCTAssertEqual(model.currentTime, 10, "The playhead must not sit outside the trim range")
    }

    func testMovingTheEndBeforeTheCursorPullsTheCursorBack() {
        let model = makeModel()
        model.seek(to: 25)
        model.setTrimEnd(15)
        XCTAssertEqual(model.currentTime, 15)
    }
}
