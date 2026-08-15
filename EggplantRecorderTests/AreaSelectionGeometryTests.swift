import XCTest

@testable import EggplantRecorder

/// Area selection geometry. Pitfall #8 is the headline: a handle drag moves the grabbed edge by the
/// delta **from mouseDown**, never "edge = current mouse point". The zero-delta test below is the
/// one that catches a regression to the latter, because "edge = mouse point" makes a zero-delta
/// drag snap the edge to wherever the cursor happens to be.
final class AreaSelectionGeometryTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let minSize: CGFloat = 40
    private let handleSize: CGFloat = 11

    // MARK: resizedByDelta — pitfall #8

    func testZeroDeltaLeavesEveryHandleUntouched() {
        let start = CGRect(x: 100, y: 100, width: 300, height: 200)
        for handle in AreaHandlePosition.allCases {
            let result = AreaSelectionGeometry.resizedByDelta(start, handle: handle, dx: 0, dy: 0)
            XCTAssertEqual(result, start, "\(handle) moved on a zero-delta drag")
        }
    }

    func testRightHandleMovesOnlyTheTrailingEdge() {
        let start = CGRect(x: 100, y: 100, width: 300, height: 200)
        let result = AreaSelectionGeometry.resizedByDelta(start, handle: .right, dx: 50, dy: 999)
        XCTAssertEqual(result, CGRect(x: 100, y: 100, width: 350, height: 200))
    }

    func testLeftHandleMovesTheOriginAndTheWidth() {
        let start = CGRect(x: 100, y: 100, width: 300, height: 200)
        let result = AreaSelectionGeometry.resizedByDelta(start, handle: .left, dx: 50, dy: 0)
        XCTAssertEqual(result, CGRect(x: 150, y: 100, width: 250, height: 200))
    }

    func testTopHandleGrowsUpwardsInCocoaCoordinates() {
        // The canvas is not flipped, so "top" is maxY.
        let start = CGRect(x: 100, y: 100, width: 300, height: 200)
        let result = AreaSelectionGeometry.resizedByDelta(start, handle: .top, dx: 999, dy: 50)
        XCTAssertEqual(result, CGRect(x: 100, y: 100, width: 300, height: 250))
    }

    func testBottomHandleMovesTheOriginAndTheHeight() {
        let start = CGRect(x: 100, y: 100, width: 300, height: 200)
        let result = AreaSelectionGeometry.resizedByDelta(start, handle: .bottom, dx: 0, dy: 50)
        XCTAssertEqual(result, CGRect(x: 100, y: 150, width: 300, height: 150))
    }

    func testCornerHandlesMoveExactlyTwoEdges() {
        let start = CGRect(x: 100, y: 100, width: 300, height: 200)

        XCTAssertEqual(
            AreaSelectionGeometry.resizedByDelta(start, handle: .topLeft, dx: 10, dy: 20),
            CGRect(x: 110, y: 100, width: 290, height: 220)
        )
        XCTAssertEqual(
            AreaSelectionGeometry.resizedByDelta(start, handle: .topRight, dx: 10, dy: 20),
            CGRect(x: 100, y: 100, width: 310, height: 220)
        )
        XCTAssertEqual(
            AreaSelectionGeometry.resizedByDelta(start, handle: .bottomLeft, dx: 10, dy: 20),
            CGRect(x: 110, y: 120, width: 290, height: 180)
        )
        XCTAssertEqual(
            AreaSelectionGeometry.resizedByDelta(start, handle: .bottomRight, dx: 10, dy: 20),
            CGRect(x: 100, y: 120, width: 310, height: 180)
        )
    }

    func testDraggingAnEdgePastItsOppositeFlipsInsteadOfInverting() {
        // A rect with negative width would break drawing and the sourceRect maths downstream.
        let start = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = AreaSelectionGeometry.resizedByDelta(start, handle: .right, dx: -110, dy: 0)
        XCTAssertEqual(result, CGRect(x: -10, y: 0, width: 10, height: 100))
        XCTAssertGreaterThanOrEqual(result.width, 0)
        XCTAssertGreaterThanOrEqual(result.height, 0)
    }

    func testDeltaIsAlwaysRelativeToTheStartRect() {
        // Applying the same delta twice to the *same* start must give the same answer — the
        // function must never accumulate.
        let start = CGRect(x: 100, y: 100, width: 300, height: 200)
        let once = AreaSelectionGeometry.resizedByDelta(start, handle: .right, dx: 25, dy: 0)
        let again = AreaSelectionGeometry.resizedByDelta(start, handle: .right, dx: 25, dy: 0)
        XCTAssertEqual(once, again)
    }

    // MARK: clamp

    func testInBoundsRectIsUntouched() {
        let rect = CGRect(x: 100, y: 100, width: 300, height: 200)
        XCTAssertEqual(AreaSelectionGeometry.clamp(rect, in: bounds, minSize: minSize), rect)
    }

    func testClampEnforcesTheMinimumSize() {
        let result = AreaSelectionGeometry.clamp(
            CGRect(x: 0, y: 0, width: 5, height: 5),
            in: bounds,
            minSize: minSize
        )
        XCTAssertEqual(result.width, minSize)
        XCTAssertEqual(result.height, minSize)
    }

    func testClampCapsAtTheBounds() {
        let result = AreaSelectionGeometry.clamp(
            CGRect(x: 0, y: 0, width: 5000, height: 5000),
            in: bounds,
            minSize: minSize
        )
        XCTAssertEqual(result, bounds)
    }

    func testClampSlidesAnOffscreenRectBackInsteadOfShrinkingIt() {
        // Dragging a selection off the left/bottom edge must keep its size and push it back in.
        let result = AreaSelectionGeometry.clamp(
            CGRect(x: -50, y: -50, width: 300, height: 200),
            in: bounds,
            minSize: minSize
        )
        XCTAssertEqual(result, CGRect(x: 0, y: 0, width: 300, height: 200))
    }

    func testClampSlidesBackFromTheFarEdges() {
        let result = AreaSelectionGeometry.clamp(
            CGRect(x: 900, y: 700, width: 300, height: 200),
            in: bounds,
            minSize: minSize
        )
        XCTAssertEqual(result, CGRect(x: 700, y: 600, width: 300, height: 200))
    }

    func testClampedRectAlwaysEndsUpInsideTheBounds() {
        let candidates = [
            CGRect(x: -500, y: -500, width: 100, height: 100),
            CGRect(x: 1500, y: 1500, width: 100, height: 100),
            CGRect(x: -10, y: 790, width: 2000, height: 5),
            CGRect(x: 995, y: 0, width: 1, height: 1000),
        ]
        for rect in candidates {
            let result = AreaSelectionGeometry.clamp(rect, in: bounds, minSize: minSize)
            XCTAssertTrue(bounds.contains(result), "\(rect) clamped to \(result), outside bounds")
            XCTAssertGreaterThanOrEqual(result.width, minSize)
            XCTAssertGreaterThanOrEqual(result.height, minSize)
        }
    }

    // MARK: enforceMinimum

    func testAClickGrowsToTheMinimumFromTheClickPoint() {
        // Pinning actual behaviour, which is not quite the "grow around the centre" you'd assume:
        // each axis's origin is recomputed from midX/midY *after* the size was raised, so a
        // zero-size click ends up at the new rect's bottom-left corner.
        let result = AreaSelectionGeometry.enforceMinimum(
            CGRect(x: 100, y: 100, width: 0, height: 0),
            in: bounds,
            minSize: minSize
        )
        XCTAssertEqual(result, CGRect(x: 100, y: 100, width: 40, height: 40))
    }

    func testGrowingNearAnEdgeStaysInBounds() {
        // Near the far corner the origin genuinely has to be pulled back to fit.
        let result = AreaSelectionGeometry.enforceMinimum(
            CGRect(x: 990, y: 790, width: 0, height: 0),
            in: bounds,
            minSize: minSize
        )
        XCTAssertEqual(result, CGRect(x: 960, y: 760, width: 40, height: 40))
        XCTAssertTrue(bounds.contains(result))
    }

    func testGrowingOnlyTheAxisThatIsTooSmall() {
        let result = AreaSelectionGeometry.enforceMinimum(
            CGRect(x: 100, y: 100, width: 300, height: 5),
            in: bounds,
            minSize: minSize
        )
        XCTAssertEqual(result.width, 300, "A wide-but-flat drag must keep its width")
        XCTAssertEqual(result.height, minSize)
    }

    func testAlreadyBigEnoughIsUntouched() {
        let rect = CGRect(x: 100, y: 100, width: 300, height: 200)
        XCTAssertEqual(
            AreaSelectionGeometry.enforceMinimum(rect, in: bounds, minSize: minSize),
            rect
        )
    }

    // MARK: handles

    func testHandlesSitOnTheSelectionCorners() {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(AreaSelectionGeometry.handlePoint(.topLeft, in: selection), CGPoint(x: 100, y: 200))
        XCTAssertEqual(AreaSelectionGeometry.handlePoint(.topRight, in: selection), CGPoint(x: 300, y: 200))
        XCTAssertEqual(AreaSelectionGeometry.handlePoint(.bottomLeft, in: selection), CGPoint(x: 100, y: 100))
        XCTAssertEqual(AreaSelectionGeometry.handlePoint(.bottomRight, in: selection), CGPoint(x: 300, y: 100))
        XCTAssertEqual(AreaSelectionGeometry.handlePoint(.top, in: selection), CGPoint(x: 200, y: 200))
        XCTAssertEqual(AreaSelectionGeometry.handlePoint(.bottom, in: selection), CGPoint(x: 200, y: 100))
        XCTAssertEqual(AreaSelectionGeometry.handlePoint(.left, in: selection), CGPoint(x: 100, y: 150))
        XCTAssertEqual(AreaSelectionGeometry.handlePoint(.right, in: selection), CGPoint(x: 300, y: 150))
    }

    func testHandleRectIsCentredOnItsPoint() {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        let rect = AreaSelectionGeometry.handleRect(.topLeft, in: selection, handleSize: handleSize)
        XCTAssertEqual(rect.midX, 100, accuracy: 0.0001)
        XCTAssertEqual(rect.midY, 200, accuracy: 0.0001)
        XCTAssertEqual(rect.width, handleSize)
    }

    func testEveryHandleIsHittableAtItsOwnPoint() {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        for handle in AreaHandlePosition.allCases {
            let point = AreaSelectionGeometry.handlePoint(handle, in: selection)
            XCTAssertEqual(
                AreaSelectionGeometry.hitHandle(at: point, in: selection, handleSize: handleSize),
                handle
            )
        }
    }

    func testTheSelectionInteriorHitsNoHandle() {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertNil(
            AreaSelectionGeometry.hitHandle(
                at: CGPoint(x: 200, y: 150),
                in: selection,
                handleSize: handleSize
            ),
            "The middle of the selection must drag the rect, not resize it"
        )
    }

    func testHandleHitTestingHasSlop() {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
        // The right handle spans 294.5…305.5, plus 4 pt of slop → up to 309.5.
        XCTAssertEqual(
            AreaSelectionGeometry.hitHandle(at: CGPoint(x: 308, y: 150), in: selection, handleSize: handleSize),
            .right
        )
        XCTAssertNil(
            AreaSelectionGeometry.hitHandle(at: CGPoint(x: 320, y: 150), in: selection, handleSize: handleSize)
        )
    }
}
