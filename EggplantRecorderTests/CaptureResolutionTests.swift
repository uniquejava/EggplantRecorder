import XCTest

@testable import EggplantRecorder

/// Capture-time resolution cap (the options bar Resolution picker). Same even/no-upscale contract
/// as the export path, enforced separately — so it needs its own coverage.
final class CaptureResolutionTests: XCTestCase {
    func testNativePassesThroughButForcesEvenDimensions() {
        let (width, height) = CaptureResolution.native.outputSize(width: 1919, height: 1081)
        XCTAssertEqual(width, 1918)
        XCTAssertEqual(height, 1080)
    }

    func testCapDownscalesKeepingAspectRatio() {
        let (width, height) = CaptureResolution.p720.outputSize(width: 1920, height: 1080)
        XCTAssertEqual(width, 1280)
        XCTAssertEqual(height, 720)
    }

    func testCapNeverUpscales() {
        // A 720p display asked for 1080p output must stay 720p.
        let (width, height) = CaptureResolution.p1080.outputSize(width: 1280, height: 720)
        XCTAssertEqual(width, 1280)
        XCTAssertEqual(height, 720)
    }

    func testDownscaleResultIsEven() {
        let (width, height) = CaptureResolution.p720.outputSize(width: 1919, height: 1080)
        XCTAssertEqual(width % 2, 0)
        XCTAssertEqual(height % 2, 0)
    }

    func testDegenerateSizeClampsToTwo() {
        let (width, height) = CaptureResolution.native.outputSize(width: 0, height: 0)
        XCTAssertEqual(width, 2)
        XCTAssertEqual(height, 2)
    }

    func testAvailableOptionsExcludeUpscales() {
        XCTAssertEqual(CaptureResolution.available(sourceHeight: 2160), [.native, .p1080, .p720])
        XCTAssertEqual(CaptureResolution.available(sourceHeight: 1080), [.native, .p720])
        XCTAssertEqual(CaptureResolution.available(sourceHeight: 720), [.native])
        XCTAssertEqual(CaptureResolution.available(sourceHeight: 480), [.native])
    }

    func testFrameRateLabels() {
        XCTAssertEqual(CaptureFrameRate.fps60.label, "60FPS")
        XCTAssertEqual(CaptureFrameRate.fps15.rawValue, 15)
    }

    func testCountdownLabels() {
        XCTAssertEqual(CaptureCountdown.none.label, L10n.tr("countdown.none"))
        XCTAssertEqual(CaptureCountdown.three.label, "3s")
        XCTAssertEqual(CaptureCountdown.none.rawValue, 0)
    }
}
