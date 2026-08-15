import XCTest

@testable import EggplantRecorder

/// The `RecorderController` half of the audit #1 fix, from the side that needs no live capture.
///
/// `start()`'s happy path drives a real `SCStream`, so it isn't covered here — see the "Limits"
/// note in `docs/code-audit.md`. What *is* covered is the guard that used to be missing: a stop
/// on a controller that isn't recording must throw rather than reach `AVAssetWriter`.
@MainActor
final class RecorderControllerGuardTests: XCTestCase {
    func testFreshControllerIsIdle() {
        let controller = RecorderController()
        XCTAssertFalse(controller.isRecording)
        XCTAssertFalse(controller.isPaused)
        XCTAssertFalse(controller.isBusy)
    }

    func testStoppingWhenNotRecordingThrows() async {
        let controller = RecorderController()
        do {
            _ = try await controller.stop()
            XCTFail("stop() on an idle controller must throw, not finalize a writer that never started")
        } catch {
            XCTAssertEqual(error as? CaptureError, .finalizeFailed)
        }
    }

    func testStoppingTwiceStillThrowsAndLeavesTheControllerIdle() async {
        let controller = RecorderController()
        for _ in 0..<3 {
            do {
                _ = try await controller.stop()
                XCTFail("Every stop on an idle controller must throw")
            } catch {
                XCTAssertEqual(error as? CaptureError, .finalizeFailed)
            }
        }
        // Critically: isRecording must not have been left true by a failed stop, or every later
        // start would be rejected as "already recording" until relaunch.
        XCTAssertFalse(controller.isRecording)
        XCTAssertFalse(controller.isBusy)
    }

    func testPauseAndResumeAreInertWhenNotRecording() {
        let controller = RecorderController()
        controller.pause()
        XCTAssertFalse(controller.isPaused, "Pause must not latch while there is nothing to pause")

        controller.resume()
        XCTAssertFalse(controller.isPaused)
        XCTAssertFalse(controller.isRecording)
    }
}
