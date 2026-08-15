import AppKit
import XCTest

@testable import EggplantRecorder

/// `restoreSelection(sourceRect:)` converts a remembered SCK rect (top-left origin, display-local)
/// back into the canvas's Cocoa coordinates (bottom-left origin). Already `internal`, so no seam.
final class AreaSelectionRestoreTests: XCTestCase {
    private func makeCanvas(width: CGFloat = 1000, height: CGFloat = 600) -> AreaSelectionCanvas {
        AreaSelectionCanvas(frame: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func testFlipsTheYAxisFromSCKToCocoa() {
        let canvas = makeCanvas()
        // 100 pt from the display's top edge, 100 pt tall, on a 600 pt-tall canvas
        // → 600 − 100 − 100 = 400 pt up from the bottom.
        XCTAssertTrue(canvas.restoreSelection(sourceRect: CGRect(x: 100, y: 100, width: 200, height: 100)))
        XCTAssertEqual(canvas.selectionInWindowCoords, CGRect(x: 100, y: 400, width: 200, height: 100))
    }

    func testARectAtTheTopOfTheDisplayLandsAtTheTopOfTheCanvas() {
        let canvas = makeCanvas()
        XCTAssertTrue(canvas.restoreSelection(sourceRect: CGRect(x: 0, y: 0, width: 200, height: 100)))
        XCTAssertEqual(canvas.selectionInWindowCoords?.maxY, 600)
    }

    func testARectAtTheBottomOfTheDisplayLandsAtTheBottomOfTheCanvas() {
        let canvas = makeCanvas()
        XCTAssertTrue(canvas.restoreSelection(sourceRect: CGRect(x: 0, y: 500, width: 200, height: 100)))
        XCTAssertEqual(canvas.selectionInWindowCoords?.minY, 0)
    }

    func testRestoringNotifiesTheObserver() {
        let canvas = makeCanvas()
        var changes = 0
        canvas.onSelectionChanged = { changes += 1 }
        canvas.restoreSelection(sourceRect: CGRect(x: 10, y: 10, width: 200, height: 100))
        XCTAssertEqual(changes, 1, "The options bar needs the size readout refreshed")
    }

    func testRestoredSelectionAlwaysEndsUpInsideTheCanvas() throws {
        let canvas = makeCanvas()
        XCTAssertTrue(canvas.restoreSelection(sourceRect: CGRect(x: 900, y: 500, width: 400, height: 300)))
        let selection = try XCTUnwrap(canvas.selectionInWindowCoords)
        XCTAssertTrue(canvas.bounds.contains(selection))
    }

    func testAnOversizedRememberedRectIsClampedRatherThanRejected() {
        // Pinning actual behaviour, which contradicts the method's own doc comment ("Reject if the
        // rect barely fits / was for a very different display size"): `clamp` already forces the
        // rect to at least minSize and fully inside bounds, so both rejection guards are
        // unreachable and a rect remembered from a much bigger display comes back clamped to
        // something unrelated instead of falling back to the default selection.
        // Recorded as a finding in docs/code-audit.md — change this test if that gets fixed.
        let canvas = makeCanvas()
        XCTAssertTrue(canvas.restoreSelection(sourceRect: CGRect(x: 3000, y: 2000, width: 800, height: 600)))
        XCTAssertNotNil(canvas.selectionInWindowCoords)
        XCTAssertTrue(canvas.bounds.contains(canvas.selectionInWindowCoords ?? .zero))
    }

    func testATinyRememberedRectIsGrownRatherThanRejected() {
        // Same root cause as above: clamp raises it to the 40 pt minimum, so the guard can't fail.
        let canvas = makeCanvas()
        XCTAssertTrue(canvas.restoreSelection(sourceRect: CGRect(x: 0, y: 0, width: 20, height: 20)))
        XCTAssertEqual(canvas.selectionInWindowCoords?.width, 40)
        XCTAssertEqual(canvas.selectionInWindowCoords?.height, 40)
    }

    func testClearingRemovesTheSelection() {
        let canvas = makeCanvas()
        canvas.restoreSelection(sourceRect: CGRect(x: 100, y: 100, width: 200, height: 100))
        XCTAssertNotNil(canvas.selectionInWindowCoords)

        canvas.clearSelection()
        XCTAssertNil(canvas.selectionInWindowCoords)
    }

    func testDefaultSelectionIsInsetFromTheCanvas() {
        let canvas = makeCanvas()
        canvas.installDefaultSelection()
        let selection = canvas.selectionInWindowCoords
        XCTAssertNotNil(selection)
        XCTAssertTrue(canvas.bounds.contains(selection ?? .zero))
        XCTAssertGreaterThan(selection?.minX ?? 0, 0, "Default selection should not touch the edges")
        XCTAssertLessThan(selection?.maxX ?? .infinity, canvas.bounds.maxX)
    }
}
