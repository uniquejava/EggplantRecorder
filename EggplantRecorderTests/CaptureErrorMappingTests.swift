import XCTest

@testable import EggplantRecorder

/// Mic start failures. Pitfall #1: without `com.apple.security.device.audio-input` under Hardened
/// Runtime the microphone is silent with no prompt — AVFoundation just reports `-3820`. Mapping it
/// to a specific `CaptureError` is what turns that into an actionable message instead of an opaque
/// OSStatus, so the mapping is worth pinning.
final class CaptureErrorMappingTests: XCTestCase {
    func testMicrophoneStartFailureIsTranslated() {
        let raw = NSError(domain: "AVFoundationErrorDomain", code: -3820, userInfo: nil)
        let mapped = CaptureSession.friendlyStartError(raw)
        XCTAssertEqual(mapped as? CaptureError, .microphoneStartFailed)
    }

    func testOtherErrorsPassThroughUnchanged() {
        let raw = NSError(domain: "SomeOtherDomain", code: -1, userInfo: nil)
        let mapped = CaptureSession.friendlyStartError(raw)
        XCTAssertNil(mapped as? CaptureError, "Unrelated errors must not be relabelled as mic failures")
        XCTAssertEqual((mapped as NSError).code, -1)
        XCTAssertEqual((mapped as NSError).domain, "SomeOtherDomain")
    }

    func testAnAlreadyTypedCaptureErrorIsNotMangled() {
        let mapped = CaptureSession.friendlyStartError(CaptureError.displayNotFound)
        XCTAssertEqual(mapped as? CaptureError, .displayNotFound)
    }

    func testEveryCaseHasAUserFacingMessage() {
        let all: [CaptureError] = [
            .alreadyRecording,
            .microphoneDenied,
            .microphoneStartFailed,
            .cannotAddVideoInput,
            .displayNotFound,
            .windowNotFound,
            .finalizeFailed,
        ]
        for error in all {
            let description = error.errorDescription
            XCTAssertNotNil(description, "\(error) has no message")
            XCTAssertFalse(description?.isEmpty ?? true, "\(error) has an empty message")
        }
    }

    func testCasesAreDistinguishable() {
        // The controllers branch on these, so accidental equality would be a real bug.
        XCTAssertNotEqual(CaptureError.alreadyRecording, .finalizeFailed)
        XCTAssertNotEqual(CaptureError.microphoneDenied, .microphoneStartFailed)
        XCTAssertEqual(CaptureError.finalizeFailed, .finalizeFailed)
    }
}
