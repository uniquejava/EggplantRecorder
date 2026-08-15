import XCTest

@testable import EggplantRecorder

/// Export sizing / bitrate / size-estimate arithmetic. All of it feeds either the encoder settings
/// or the "About 12 MB" label in the editor, and none of it needs a video file.
final class ExportSettingsTests: XCTestCase {
    private func source(
        width: Int = 1920,
        height: Int = 1080,
        frameRate: Double = 60,
        fileSize: Int64 = 100_000_000
    ) -> RecordingMediaInfo {
        RecordingMediaInfo(
            width: width,
            height: height,
            frameRate: frameRate,
            audioTrackCount: 2,
            fileSize: fileSize
        )
    }

    // MARK: outputSize

    func testOriginalResolutionForcesEvenDimensions() {
        // H.264 rejects odd dimensions, so "Original" still has to round down.
        let settings = ExportSettings()
        let (width, height) = settings.outputSize(sourceWidth: 1921, sourceHeight: 1081)
        XCTAssertEqual(width, 1920)
        XCTAssertEqual(height, 1080)
    }

    func testDownscaleKeepsAspectRatio() {
        var settings = ExportSettings()
        settings.resolution = .p720
        let (width, height) = settings.outputSize(sourceWidth: 1920, sourceHeight: 1080)
        XCTAssertEqual(width, 1280)
        XCTAssertEqual(height, 720)
    }

    func testDownscaleResultIsMadeEven() {
        var settings = ExportSettings()
        settings.resolution = .p720
        // 1919 × 0.666… = 1279.33 → 1279 → must come back as 1278.
        let (width, height) = settings.outputSize(sourceWidth: 1919, sourceHeight: 1080)
        XCTAssertEqual(width % 2, 0)
        XCTAssertEqual(height, 720)
        XCTAssertEqual(width, 1278)
    }

    func testResolutionCapNeverUpscales() {
        var settings = ExportSettings()
        settings.resolution = .p1080
        // Source is already 1080p — pass through untouched rather than scaling to exactly 1080.
        let (width, height) = settings.outputSize(sourceWidth: 1920, sourceHeight: 1080)
        XCTAssertEqual(width, 1920)
        XCTAssertEqual(height, 1080)
    }

    func testTinySourceNeverGoesBelowTwoPixels() {
        let settings = ExportSettings()
        let (width, height) = settings.outputSize(sourceWidth: 1, sourceHeight: 1)
        XCTAssertEqual(width, 2)
        XCTAssertEqual(height, 2)
    }

    // MARK: targetFrameRate

    func testOriginalFrameRateHasNoTarget() {
        XCTAssertNil(ExportSettings().targetFrameRate(sourceFPS: 60))
    }

    func testFrameRateCapAppliesOnlyWhenSourceIsFaster() {
        var settings = ExportSettings()
        settings.frameRate = .fps30
        XCTAssertEqual(settings.targetFrameRate(sourceFPS: 60), 30)
        XCTAssertEqual(settings.targetFrameRate(sourceFPS: 31), 30)
        // Within the 0.5 fps dead-band: don't re-time a 30 fps source to 30.
        XCTAssertNil(settings.targetFrameRate(sourceFPS: 30))
        XCTAssertNil(settings.targetFrameRate(sourceFPS: 24))
    }

    // MARK: videoBitrate

    func testBitrateScalesWithPixelCount() {
        let settings = ExportSettings()
        let small = settings.videoBitrate(width: 640, height: 360, sourceFPS: 30)
        let large = settings.videoBitrate(width: 1920, height: 1080, sourceFPS: 30)
        XCTAssertGreaterThan(large, small)
    }

    func testBitrateScalesWithQuality() {
        var high = ExportSettings()
        high.quality = .high
        var low = ExportSettings()
        low.quality = .low
        XCTAssertGreaterThan(
            high.videoBitrate(width: 1920, height: 1080, sourceFPS: 30),
            low.videoBitrate(width: 1920, height: 1080, sourceFPS: 30)
        )
    }

    func testBitrateHasAFloor() {
        var settings = ExportSettings()
        settings.quality = .low
        settings.frameRate = .fps15
        // 2×2 at the 0.25 fps floor would compute 100 kbps; the floor must hold it at 250 kbps.
        XCTAssertEqual(settings.videoBitrate(width: 2, height: 2, sourceFPS: 60), 250_000)
    }

    // MARK: estimatedBytes

    func testEstimateIsZeroWithoutASourceFileSize() {
        let settings = ExportSettings()
        let estimate = settings.estimatedBytes(
            trimDuration: 5,
            fullDuration: 10,
            source: source(fileSize: 0)
        )
        XCTAssertEqual(estimate, 0)
    }

    func testEstimateGrowsWithTrimLength() {
        let settings = ExportSettings()
        let half = settings.estimatedBytes(trimDuration: 5, fullDuration: 10, source: source())
        let whole = settings.estimatedBytes(trimDuration: 10, fullDuration: 10, source: source())
        XCTAssertGreaterThan(whole, half)
    }

    func testEstimateShrinksWhenDownscaling() {
        var original = ExportSettings()
        original.resolution = .original
        var scaled = ExportSettings()
        scaled.resolution = .p720
        XCTAssertGreaterThan(
            original.estimatedBytes(trimDuration: 10, fullDuration: 10, source: source()),
            scaled.estimatedBytes(trimDuration: 10, fullDuration: 10, source: source())
        )
    }

    func testEstimateHasAFloor() {
        let settings = ExportSettings()
        let estimate = settings.estimatedBytes(
            trimDuration: 0.001,
            fullDuration: 3600,
            source: source(fileSize: 1_000)
        )
        XCTAssertEqual(estimate, 50_000)
    }

    func testEstimateSurvivesAZeroFullDuration() {
        // `fullDuration` is divided by — the guard is a 0.001 floor, not a crash.
        let settings = ExportSettings()
        let estimate = settings.estimatedBytes(trimDuration: 0, fullDuration: 0, source: source())
        XCTAssertGreaterThanOrEqual(estimate, 0)
    }

    func testEstimatedSizeTextIsPlaceholderWithoutASource() {
        let settings = ExportSettings()
        XCTAssertEqual(
            settings.estimatedSizeText(trimDuration: 5, fullDuration: 10, source: nil),
            "About —"
        )
        XCTAssertEqual(
            settings.estimatedSizeText(trimDuration: 0, fullDuration: 10, source: source()),
            "About —"
        )
    }

    // MARK: available options

    func testFrameRateChoicesHideAnythingThatWouldUpscale() {
        let settings = ExportSettings()
        let at30 = settings.availableFrameRates(source: source(frameRate: 30))
        XCTAssertEqual(at30, [.original, .fps24, .fps15])

        let at60 = settings.availableFrameRates(source: source(frameRate: 60))
        XCTAssertEqual(at60, [.original, .fps30, .fps24, .fps15])
    }

    func testResolutionChoicesHideAnythingThatWouldUpscale() {
        let settings = ExportSettings()
        XCTAssertEqual(settings.availableResolutions(source: source(height: 1080)), [.original, .p720])
        XCTAssertEqual(
            settings.availableResolutions(source: source(height: 2160)),
            [.original, .p1080, .p720]
        )
    }

    func testOriginalIsAlwaysOffered() {
        let settings = ExportSettings()
        XCTAssertTrue(settings.availableFrameRates(source: source(frameRate: 1)).contains(.original))
        XCTAssertTrue(settings.availableResolutions(source: source(height: 100)).contains(.original))
    }

    // MARK: audio

    func testAudioIsOnlyReprocessedWhenItActuallyChanges() {
        var settings = ExportSettings()
        XCTAssertFalse(settings.processesAudio, "Full volume + stereo should passthrough")

        settings.volume = 0.5
        XCTAssertTrue(settings.processesAudio)

        settings.volume = 1
        settings.audioChannels = .mono
        XCTAssertTrue(settings.processesAudio)
    }

    // MARK: labels

    func testTitlesFallBackWithoutASource() {
        let settings = ExportSettings()
        XCTAssertEqual(settings.frameRateTitle(source: nil), "Original")
        XCTAssertEqual(settings.resolutionTitle(source: nil), "Original")
    }

    func testTitlesIncludeTheSourceDetailWhenKnown() {
        let settings = ExportSettings()
        XCTAssertEqual(
            settings.frameRateTitle(source: source(frameRate: 60)),
            "Original (60 FPS)"
        )
        XCTAssertEqual(
            settings.resolutionTitle(source: source(width: 1920, height: 1080)),
            "Original (1920×1080)"
        )
    }

    func testMediaInfoRoundsFrameRateForDisplay() {
        XCTAssertEqual(source(frameRate: 29.97).displayFPS, 30)
        XCTAssertEqual(source(frameRate: 0).displayFPS, 1, "Never show 0 FPS")
    }
}
