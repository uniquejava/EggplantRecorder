import XCTest

@testable import EggplantRecorder

/// The audit #1 gate. `AppPhase.starting` / `.stopping` are set *synchronously* before the first
/// `await` in the capture path, and every entry point / control keys off these two properties.
/// Finishing an `AVAssetWriter` twice raises an ObjC exception Swift cannot catch — a hard crash
/// that loses the recording — so this truth table is the cheapest guard against a regression.
final class AppPhaseTests: XCTestCase {
    private let allPhases: [AppPhase] = [.idle, .configuring, .countdown, .starting, .recording, .stopping]

    func testOnlyTheAwaitingPhasesAreTransitioning() {
        XCTAssertTrue(AppPhase.starting.isTransitioning)
        XCTAssertTrue(AppPhase.stopping.isTransitioning)

        XCTAssertFalse(AppPhase.idle.isTransitioning)
        XCTAssertFalse(AppPhase.configuring.isTransitioning)
        XCTAssertFalse(AppPhase.countdown.isTransitioning)
        XCTAssertFalse(AppPhase.recording.isTransitioning)
    }

    func testEveryPhaseIsAccountedForInTheTransitioningTable() {
        // Guards against a new AppPhase case silently defaulting to "not transitioning".
        let transitioning = allPhases.filter(\.isTransitioning)
        XCTAssertEqual(transitioning.count, 2, "A new AppPhase case needs an isTransitioning decision")
    }

    @MainActor
    func testSetupIsOnlyReachableFromASettledPhase() {
        let state = AppState.shared
        let original = state.phase
        defer { state.phase = original }

        state.phase = .idle
        XCTAssertTrue(state.canBeginSetup)

        state.phase = .configuring
        XCTAssertTrue(state.canBeginSetup, "Re-picking a source while the options bar is up is fine")

        // Everything below has an outstanding await or a live capture behind it.
        state.phase = .countdown
        XCTAssertFalse(state.canBeginSetup, "A second Record tap during a countdown ran two countdowns")

        state.phase = .starting
        XCTAssertFalse(state.canBeginSetup)

        state.phase = .recording
        XCTAssertFalse(state.canBeginSetup)

        state.phase = .stopping
        XCTAssertFalse(state.canBeginSetup)
    }

    @MainActor
    func testShowOptionsIsRejectedWhileATransitionIsInFlight() {
        let state = AppState.shared
        let original = state.phase
        defer { state.phase = original }

        for phase in [AppPhase.starting, .stopping, .recording, .countdown] {
            state.phase = phase
            state.showOptions(mode: .screen)
            XCTAssertFalse(
                state.canBeginSetup,
                "showOptions must not move the phase out from under an in-flight start/stop"
            )
        }
    }

    @MainActor
    func testSelectionEntryPointsAreRejectedWhileRecording() {
        let state = AppState.shared
        let original = state.phase
        defer { state.phase = original }

        state.phase = .recording
        state.showAreaSelection()
        XCTAssertFalse(state.canBeginSetup)

        state.phase = .recording
        state.showWindowSelection()
        XCTAssertFalse(state.canBeginSetup)

        state.phase = .recording
        state.showWindowAreaSelection()
        XCTAssertFalse(state.canBeginSetup)
    }

    @MainActor
    func testStopIsIgnoredWhenNotRecording() async {
        let state = AppState.shared
        let original = state.phase
        defer { state.phase = original }

        // `.stopping` means a stop is already awaiting — a second Stop tap must fall straight
        // through rather than finishing the writer again.
        state.phase = .stopping
        await state.stopRecording()
        XCTAssertFalse(state.canBeginSetup)

        state.phase = .idle
        await state.stopRecording()
        await state.cancelRecording()
        await state.restartRecording()
        XCTAssertTrue(state.canBeginSetup, "No-op stops must leave the phase alone")
    }
}
