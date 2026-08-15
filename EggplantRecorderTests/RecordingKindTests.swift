import XCTest

@testable import EggplantRecorder

final class RecordingKindTests: XCTestCase {
    func testPrefixesRoundTripThroughFilenames() {
        for kind in [RecordingKind.screen, .window, .area] {
            let base = "\(kind.filePrefix)-2026-08-15-143000"
            XCTAssertEqual(RecordingKind.from(filename: base), kind, "\(kind) lost its prefix")
        }
    }

    func testPrefixMatchingIsCaseInsensitive() {
        XCTAssertEqual(RecordingKind.from(filename: "WINDOW-2026-08-15"), .window)
        XCTAssertEqual(RecordingKind.from(filename: "area-2026-08-15"), .area)
    }

    func testUnprefixedNamesFallBackToScreen() {
        // Audit #5, pinned deliberately: kind is inferred from a *mutable* filename, so renaming an
        // Area or Window clip to anything without the prefix silently reclassifies it as Screen.
        // If kind ever becomes real metadata (xattr), this expectation should change with it.
        XCTAssertEqual(RecordingKind.from(filename: "Holiday clip"), .screen)
        XCTAssertEqual(RecordingKind.from(filename: "My Area recording"), .screen)
        XCTAssertEqual(RecordingKind.from(filename: ""), .screen)
    }

    func testPrefixMustBeAtTheStart() {
        XCTAssertEqual(RecordingKind.from(filename: "Clip-window-2"), .screen)
    }

    func testDisplayNames() {
        XCTAssertEqual(RecordingKind.screen.displayName, L10n.tr("kind.screen"))
        XCTAssertEqual(RecordingKind.window.displayName, L10n.tr("kind.window"))
        XCTAssertEqual(RecordingKind.area.displayName, L10n.tr("kind.area"))
    }

    func testSortsByDisplayName() {
        XCTAssertEqual([RecordingKind.window, .screen, .area].sorted(), [.area, .screen, .window])
    }
}
