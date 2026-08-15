import CoreGraphics
import XCTest

@testable import EggplantRecorder

/// `WindowHit` is the handoff between the hover-picker and ScreenCaptureKit. `sourceID` is the
/// exact string `CaptureFilter` parses a `CGWindowID` back out of, so its format is a contract.
final class WindowHitTests: XCTestCase {
    private func hit(
        windowID: CGWindowID = 42,
        title: String = "",
        ownerName: String = ""
    ) -> WindowHit {
        WindowHit(
            windowID: windowID,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            title: title,
            ownerName: ownerName
        )
    }

    func testSourceIDFormat() {
        XCTAssertEqual(hit(windowID: 42).sourceID, "window:42")
        XCTAssertEqual(hit(windowID: 0).sourceID, "window:0")
    }

    func testSourceIDRoundTripsBackToAWindowID() {
        let original: CGWindowID = 987_654
        let sourceID = hit(windowID: original).sourceID
        let parsed = UInt32(String(sourceID.dropFirst("window:".count)))
        XCTAssertEqual(parsed, original)
    }

    func testDisplayNameJoinsOwnerAndTitle() {
        XCTAssertEqual(
            hit(title: "Untitled.txt", ownerName: "TextEdit").displayName,
            "TextEdit — Untitled.txt"
        )
    }

    func testDisplayNameFallsBackToTheOwnerWhenThereIsNoTitle() {
        XCTAssertEqual(hit(title: "", ownerName: "Safari").displayName, "Safari")
    }

    func testDisplayNameFallsBackToAGenericLabelWhenNothingIsKnown() {
        XCTAssertEqual(hit(title: "", ownerName: "").displayName, "Window")
    }

    func testDisplayNameIsNeverEmpty() {
        let cases = [
            hit(title: "", ownerName: ""),
            hit(title: "Doc", ownerName: ""),
            hit(title: "", ownerName: "App"),
            hit(title: "Doc", ownerName: "App"),
        ]
        for candidate in cases {
            XCTAssertFalse(candidate.displayName.isEmpty)
        }
    }

    func testEquatableComparesEveryField() {
        XCTAssertEqual(hit(windowID: 1, title: "a", ownerName: "b"), hit(windowID: 1, title: "a", ownerName: "b"))
        XCTAssertNotEqual(hit(windowID: 1), hit(windowID: 2))
        XCTAssertNotEqual(hit(title: "a"), hit(title: "b"))
    }
}
