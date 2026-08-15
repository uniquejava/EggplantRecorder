import XCTest

@testable import EggplantRecorder

/// The layer of the audit #1 fix that a double-tap actually lands on: the options-bar Record button.
///
/// `OptionsBarModel.isBusy` is set *before* the mic-permission await, so the window between "Record
/// tapped" and "capture live" is covered too. Without it, a second tap fired `onRecord` again and
/// `AppState.startRecording` built a second `SCStream` + `AVAssetWriter` on the same output path.
///
/// `microphone` is forced off in the fixture: with it on, `startRecording()` takes the
/// `await CapturePermissions.requestMicrophoneAccess()` branch, which hits real TCC and makes the
/// call asynchronous. With it off, `fireRecord` runs synchronously and the double-tap is exact.
@MainActor
final class OptionsBarRecordGateTests: XCTestCase {
    private func makeModel() -> (OptionsBarModel, () -> Int) {
        let model = OptionsBarModel(appState: .shared)
        model.microphone = false
        model.systemAudio = false
        model.sources = [
            CaptureSource(id: "display:1", kind: .screen, name: "Built-in Display", width: 1920, height: 1080)
        ]
        model.selectedSourceID = "display:1"

        let counter = FireCounter()
        model.onRecord = { _ in counter.count += 1 }
        return (model, { counter.count })
    }

    private final class FireCounter {
        var count = 0
    }

    func testDoubleTapOnRecordFiresOnce() {
        let (model, fired) = makeModel()

        model.startRecording()
        model.startRecording()

        XCTAssertEqual(fired(), 1, "A second Record tap must be swallowed by the isBusy gate")
    }

    func testRapidRepeatedTapsStillFireOnce() {
        let (model, fired) = makeModel()
        for _ in 0..<10 {
            model.startRecording()
        }
        XCTAssertEqual(fired(), 1)
    }

    func testRecordSetsBusySynchronously() {
        // Synchronously, before any await — that is the whole point of the flag.
        let (model, _) = makeModel()
        XCTAssertFalse(model.isBusy)

        model.startRecording()

        XCTAssertTrue(model.isBusy)
    }

    func testAnAlreadyBusyModelDoesNotFireAtAll() {
        let (model, fired) = makeModel()
        model.isBusy = true

        model.startRecording()

        XCTAssertEqual(fired(), 0)
    }

    func testClearingBusyAllowsRecordingAgain() {
        // Restart / a failed start clears the flag; the button has to come back to life.
        let (model, fired) = makeModel()
        model.startRecording()
        XCTAssertEqual(fired(), 1)

        model.isBusy = false
        model.startRecording()
        XCTAssertEqual(fired(), 2)
    }

    func testWithoutASourceItWarnsInsteadOfRecording() {
        let (model, fired) = makeModel()
        model.sources = []

        model.startRecording()

        XCTAssertEqual(fired(), 0)
        XCTAssertNotNil(model.bannerMessage)
        XCTAssertFalse(model.isBusy, "A rejected start must not leave the button inert")
    }

    func testAnUnknownSelectionWarnsInsteadOfRecording() {
        let (model, fired) = makeModel()
        model.selectedSourceID = "display:999"

        model.startRecording()

        XCTAssertEqual(fired(), 0)
        XCTAssertNotNil(model.bannerMessage)
    }

    func testRecordedConfigCarriesTheChosenOptions() {
        // Assigning `frameRate` / `resolution` runs the model's `persist()` didSet, which writes the
        // user's real capture defaults — these tests run inside the real app, so put them back.
        let prefs = AppPreferences.shared
        let originalFrameRate = prefs.defaultFrameRate
        let originalResolution = prefs.defaultResolution
        let originalCountdown = prefs.defaultCountdown
        defer {
            prefs.defaultFrameRate = originalFrameRate
            prefs.defaultResolution = originalResolution
            prefs.defaultCountdown = originalCountdown
        }

        let model = OptionsBarModel(appState: .shared)
        model.microphone = false
        model.systemAudio = true
        model.showCursor = false
        model.frameRate = .fps60
        model.sources = [
            CaptureSource(id: "display:1", kind: .screen, name: "Built-in Display", width: 1920, height: 1080)
        ]
        model.selectedSourceID = "display:1"

        let box = ConfigBox()
        model.onRecord = { box.config = $0 }
        model.startRecording()

        guard let config = box.config else {
            return XCTFail("onRecord never fired")
        }
        XCTAssertEqual(config.sourceID, "display:1")
        XCTAssertEqual(config.kind, .screen)
        XCTAssertEqual(config.frameRate, .fps60)
        XCTAssertFalse(config.showCursor)
        XCTAssertTrue(config.systemAudio)
        XCTAssertNil(config.microphoneDeviceID, "Mic off must not leak a device ID into the config")
    }

    private final class ConfigBox {
        var config: RecordingConfig?
    }
}
