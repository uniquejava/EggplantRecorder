# Code audit — 2026-08-15

Findings from an audit of the Cursor-built codebase. Every item below was **verified against
the source**, not inferred. Ordered by value; `file:line` refers to the tree at commit after
"Follow the recorded window with the mini panel".

Fix items top-down. Tick them off here as they land so the next session doesn't re-audit.

**Fixed so far:** #1 (double-tap Stop/Record crash), #2 (test target — 156 tests), #4 (duplicated
library-path key), #8 (force unwrap). **Still open:** #3, #5, #6, #7, #9, plus #10-12 found while
writing the tests.

---

## 1. Double-tap Stop / Record can crash or orphan a capture — HIGH

**Status: fixed 2026-08-15.** Two layers, callers first:

*Phase gate (`AppState`).* `AppPhase` gained `.starting` and `.stopping`, both set **synchronously
before** the first `await` — `.starting` at the top of the `do` in `startRecording`, `.stopping` in the
new shared `beginStopping()` that fronts `stopRecording` / `cancelRecording` / `restartRecording`. The
existing `phase == .recording` guards now reject the second tap on their own. Entry into setup went
from `phase != .recording, phase != .countdown` to a single `canBeginSetup` (`.idle` / `.configuring`
only), which also blocks a second Record tap *during a countdown* — that used to run two countdowns.

*Controls.* Menu-bar Pause / Stop disable themselves while `phase.isTransitioning`
(`RecordingControlBarView.reload()`); the mini panel was already torn down synchronously by
`recordingChrome.hide()`. The options-bar Record button is gated by a new `OptionsBarModel.isBusy`,
set before the mic-permission `await` so the pre-`onRecord` window is covered too, and cleared in
`prepare(mode:)`.

*Recorder layers.* `RecorderController` has an `isBusy` flag around both start and stop; its `start`
now **throws** `alreadyRecording` instead of returning silently (a silent return let the caller flip
its own state to "recording" with nothing captured). `CaptureSession.start()` has a `starting` flag
covering the gap before `writing` is set, and `stopAndFinish()` is idempotent: a `finished` flag, and
writer + inputs are handed to locals and the fields nil'd so nothing can be finished twice.

Two adjacent crashes fell out of the same pass:

- `stopAndFinish()` on a session whose first frame never arrived (Stop within milliseconds, or a
  minimized window with no frames) called `markAsFinished()` before `startWriting()` — the same
  uncatchable ObjC exception. It now throws `finalizeFailed` instead.
- `RecorderController.stop()` left `isRecording` true when finalizing threw, so every later start was
  rejected as "already recording" until relaunch. Cleared in a `defer` now.

**Verified by reproduction, 2026-08-15.** Crash confirmed on the pre-fix build and gone after.

Harness: `cliclick` for navigation, `screencapture` to locate panels, an AX probe for status-item
geometry (`AXExtrasMenuBar` → pos/size = exact click points; the embedded Pause/Stop buttons are *not*
AX-exposed, so `AXPress` is unavailable), and a small `CGEvent` tool for the double-tap. **`cliclick`
cannot express this race** — it posts clicks without setting `mouseEventClickState`, so AppKit sees
`clickCount=0` and silently drops the second click. The double-tap must be posted as two well-formed
click pairs (`mouseEventClickState = 1`) — that was the difference between "no repro" and repro.

- **Pre-fix (`9c109b3`), Screen recording, two Stop clicks 40 ms apart:** hard crash.
  ```
  NSInternalInconsistencyException: *** -[AVAssetWriter finishWritingWithCompletionHandler:]
  Cannot call method when status is 2        (status 2 = AVAssetWriterStatusCompleted)
      at CaptureSession.stopAndFinish
  ```
  Exactly the predicted mechanism — the second pass finishing an already-completed writer.
- **Fixed build, identical injection:** survives. One Stop action, `recorder.stop()` 53 ms, status item
  back to the 40 pt idle glyph, valid MP4. Also clean at a 5 ms gap.
- **The window is ~40–55 ms** (measured: `recorder.stop()` took 37/41/45/45/53 ms across runs on short
  recordings). It is `stopCapture` round-trip + `finishWriting`, so it grows with recording length —
  a long take widens the window and makes an ordinary impatient double-tap far more likely to land.

Which layer saved it, precisely: the **disabled Stop button** (`phase.isTransitioning` in
`RecordingControlBarView.reload()`) — the second click hits a disabled control, so no action fires. The
phase guard is the backstop for paths where the control isn't disabled or destroyed, and was not the
layer exercised in this test. The mini panel is self-protecting for a different reason:
`beginStopping()` calls `recordingChrome.hide()` synchronously, so its Stop button is gone within the
window (verified — a mini-panel double-tap produced one action in both builds).

## 2. No test target exists

**Status: fixed 2026-08-15.** `EggplantRecorderTests` — a hosted XCTest bundle
(`com.apple.product-type.bundle.unit-test`, `TEST_HOST` = the app, so `@testable import` works in a
single-app-target project). **156 tests, 0 failures, 0.16 s.**

```bash
xcodebuild -scheme EggplantRecorder -configuration Debug -derivedDataPath build test
```

The target uses a second `PBXFileSystemSynchronizedRootGroup`, so new files under
`EggplantRecorderTests/` need no project edits — same as the app. A **shared** scheme now exists at
`EggplantRecorder.xcodeproj/xcshareddata/xcschemes/EggplantRecorder.xcscheme` with the test target in
its `TestAction`; before this the only scheme lived in gitignored `xcuserdata`, i.e. `xcodebuild test`
depended on per-machine scheme autocreation.

Covered, one file per unit: `CaptureTiming` (pause/resume PTS + monotonicity), `ExportSettings`,
`CaptureResolution` / `CaptureFrameRate` / `CaptureCountdown`, `RecordingsLibraryPaths` +
`RecordingsLibrary` (sanitise / edit-URL / **traversal guard**), `RecordingKind`, `MediaProbe` clock
formatting, `AppPhase` + `AppState` entry gates, `RecorderController` guards, **`OptionsBarModel`
Record gate**, `AreaSelectionGeometry`, `AreaSelectionCanvas.restoreSelection`, `WindowHit`,
`EditorModel` trim clamping, `CaptureSession.friendlyStartError`.

Three seams were needed, all behaviour-preserving: `RecordingsLibraryPaths` became the single owner of
the library path (that's #4 below), area geometry moved out of the `NSView` into
`AreaSelectionGeometry`, and `ensureLibraryPath` / `friendlyStartError` went from `private` to
internal. `CaptureError` gained `Equatable` so error assertions read normally.

**How much of the audit #1 state machine this actually covers.** The `OptionsBarModel` test is the
valuable one: two `startRecording()` calls in a row must fire `onRecord` exactly once, which is the
`isBusy` gate a real double-tap lands on. `AppPhase` / `canBeginSetup` are covered as a truth table
plus rejection tests on the real `AppState` singleton. What is **not** covered:

- **The capture pipeline.** `RecorderController` holds `private let session = CaptureSession()` with no
  injection point, and `CaptureSession` needs a live `SCStream`, a real display and Screen Recording
  TCC. Only the guard side is tested (a `stop()` on a non-recording controller throws rather than
  finalizing a writer that never started, and a failed stop doesn't leave `isRecording` latched).
  Covering the happy path means extracting a session protocol — a real structural change, worth its
  own item rather than being smuggled in here.
- **Driven `AppState` transitions.** It's a `@MainActor` singleton with `private init` wiring nine
  AppKit controllers; calling `startRecording` for real would start a capture.

**Still uncovered, and why** — each needs a *structural* change first, so don't re-survey these:

| Logic | Blocker |
|---|---|
| `FilesListView` 3-click sort cycle (`FilesListView.swift:246-284`) | `private` + `@State` on a SwiftUI value type; needs a `SortCycleTracker` extracted |
| `TrimTimelineView` `x(for:)` / `time(for:)` / `hitKind` (`:132-159`) | same — `private` on a `View`; needs a `TrimGeometry` helper |
| `ExportService` trim clamp + even-dimension snap (`:70-71, 86-92`) | inline statements inside a large async function |
| `CaptureSources.shouldList(window:)` (`:121-186`) | takes a live `SCWindow`, which has no public init |
| `CaptureSession` bitrate formula (`:180`) | a local `let` inside `beginWriting` |
| `WindowHitTester.cgRect(fromWindowBounds:)` (`:88-109`) | `private static`; `quartzRectToCocoa` reads live screens instead of taking a height |
| `OptionsBarModel.clampResolutionIfNeeded` (`:372`) | `private`; only reachable via `selectResolution` |
| `AreaOverlayWindow.makeResult()` (`:78-105`) | the Cocoa→SCK flip and ×`backingScaleFactor` rounding read a live `NSScreen` |

## 3. `RecordingsLibrary.list()` probes durations serially

`Services/RecordingsLibrary.swift:56-86` — `for url in urls { … await MediaProbe.duration(of: url) … }`
awaits one `AVURLAsset.load(.duration)` at a time. Runs after every recording, every Files List open,
and every edit, so the stall grows linearly with library size. Use a task group and reassemble in order.

## 4. Library-path UserDefaults key is typed twice

**Status: fixed 2026-08-15** (as the seam that made the path logic testable). `RecordingsLibraryPaths`
in `Models/AppPreferences.swift` is now the single owner:

```swift
enum RecordingsLibraryPaths {
    static let defaultFolderURL: URL
    static let folderPathKey = "click.yinsb.eggplantrecorder.libraryFolderPath"
    static func resolve(rawPath: String?) -> URL   // pure — trim, empty → default
    static var currentFolderURL: URL               // resolve(UserDefaults.standard…)
}
```

`RecordingsLibrary.directoryURL` and `AppPreferences.libraryDirectoryURL` both delegate to it, and
`AppPreferences.Key.libraryFolderPath` is now an alias for `folderPathKey`. Deliberately **not**
actor-isolated, so `RecordingsLibrary` can still use it from off the main actor — which was the
original reason for the duplication. `RecordingsLibraryPathTests` asserts both resolve to the same
place, so a future desync fails the build rather than silently splitting the library.

## 5. Recording kind is inferred from the filename

`Models/RecordingKind.swift:28-33` (`from(filename:)`) decides kind by `"window-"` / `"area-"` prefix,
defaulting to `.screen`. But `RecordingsLibrary.rename(path:to:)` lets the user rename freely — rename
an Area or Window clip to anything without that prefix and it silently reclassifies as `.screen`
forever. Kind should be real metadata (xattr) rather than inferred from a mutable name.

## 6. Duplicated multi-screen overlay boilerplate

`UI/AreaSelection/AreaSelectionController.swift:20-67` and
`UI/WindowSelection/WindowSelectionController.swift:18-51` independently implement the same lifecycle:
spawn one borderless window per `NSScreen.screens`, track the array, install/remove an Escape
`keyDown` monitor, `NSApp.activate(ignoringOtherApps:)`, tear down in `hide()`. Structurally identical
modulo the per-window payload. A shared generic base removes ~40 lines and one place to regress the
documented Escape-cancel behavior.

## 7. Dead `anchorRect` plumbing

`AppState.showOptions(mode:anchorRect:)` accepts and forwards it; `showWindowSelection`'s `onComplete`
computes `result.hit.frame` to pass it; `UI/OptionsBar/OptionsBarController.swift:20` does
`_ = anchorRect` with a comment that the panel always opens bottom-center. Left over from an
abandoned anchor-near-window design. Remove end-to-end or wire it up.

## 8. Lone force unwrap

**Status: fixed 2026-08-15.** `AreaSelectionCanvas.mouseDown` now builds the empty rect once and
assigns it to both `selectionInWindowCoords` and `selectionAtDragStart`, instead of force-unwrapping
the property it had just set on the line above. Fixed in passing while the geometry was being
extracted for #2.

## 9. Sandbox forward-risk: raw path for the user-chosen save folder

`EggplantRecorder.entitlements` sets `com.apple.security.app-sandbox = false`, and
`AppPreferences.chooseLibraryFolder()` (`Models/AppPreferences.swift:112-124`) stores a plain
`url.path`. Fine now; breaks on first relaunch if sandboxing is ever enabled (App Store, hardening
pass) because a raw path carries no access grant — it needs a security-scoped bookmark
(`bookmarkData(options: .withSecurityScope)` + `startAccessingSecurityScopedResource()`). Cheap to
bake in now, painful once users have old-format UserDefaults to migrate.

---

## Found while writing the tests for #2 (2026-08-15)

All three are **pinned by tests as current behaviour**, not fixed — the tests assert what the code
actually does, with a comment pointing here. Fix any of them and the matching test must change too.

### 10. `restoreSelection` never rejects anything — MEDIUM

`UI/AreaSelection/AreaSelectionCanvas.swift:41-57`. The doc comment says "Reject if the rect barely
fits / was for a very different display size", and there are two guards for it:

```swift
let clamped = clamp(cocoa)
guard clamped.width >= minSize, clamped.height >= minSize else { return false }
let overlap = clamped.intersection(bounds)
guard overlap.width >= minSize, overlap.height >= minSize else { return false }
```

Both are unreachable. `clamp` already forces the rect to at least `minSize` on both axes **and** fully
inside `bounds`, so `clamped.width >= minSize` is always true and `overlap == clamped`. Consequence: a
rect remembered from a larger display (or a different resolution) comes back *clamped to something
unrelated* rather than returning `false` and letting the caller fall back to the default selection —
e.g. a remembered `(3000, 2000, 800×600)` on a 1000×600 canvas becomes `(200, 0, 800×600)`.

The fix is to validate the **pre-clamp** rect against `bounds` and only then clamp. Test:
`AreaSelectionRestoreTests.testAnOversizedRememberedRectIsClampedRatherThanRejected`.

### 11. `enforceMinimum` grows from the corner, not the centre — LOW

`UI/AreaSelection/AreaSelectionGeometry.swift` (lifted verbatim from the old `mouseUp` fixup). Each
axis reads `midX` / `midY` *after* raising the size, so the "centre" it grows around has already moved
by half the new size:

```swift
r.size.width = minSize                                   // r.midX shifts by minSize/2 here
r.origin.x = min(max(bounds.minX, r.midX - minSize / 2), bounds.maxX - minSize)
```

Net effect: a bare click at (100, 100) yields `(100, 100, 40×40)` — the click becomes the rect's
bottom-left corner. Reading the size into a local before computing the origin would centre it.
Cosmetic only. Test: `AreaSelectionGeometryTests.testAClickGrowsToTheMinimumFromTheClickPoint`.

### 12. The symlink fallback in `ensureLibraryPath` only works for files that exist — LOW

`Services/RecordingsLibrary.swift:198-212`. `resolvingSymlinksInPath()` resolves a symlink only when
the **whole** path exists on disk; with a missing last component it returns the path unchanged
(verified directly). So the same symlinked library location is *accepted* for an existing file and
*rejected* for one not yet created.

Harmless today — every caller of the guard (`delete` / `rename` / `revealInFinder` / `play` /
`quickLook` / `makeEditOutputURL`) operates on a file that already exists, and recordings are written
to `directoryURL` without going through the guard. It would bite anything that validates a
not-yet-created output path, which is plausible if the save folder is ever a symlink. Test:
`RecordingsLibraryPathTests.testASymlinkedPathToAMissingFileIsRejected`.

Related, and *not* a finding but worth knowing: the guard's first check uses `standardizedFileURL`,
which does **not** follow symlinks. A symlink *inside* the library pointing outside it therefore
passes the prefix check and is accepted. That is only reachable if the user plants such a link in
their own recordings folder, so it's noted rather than filed.

---

## Noted as fine (don't re-flag)

- `CaptureSession` sample delivery is correctly serialized — `pause()` / `resume()` and
  `stream(_:didOutputSampleBuffer:)` all run on the same private `queue` passed as
  `sampleHandlerQueue`, so there's no data race despite the class not being `@MainActor`.
- `RecordingsLibrary.ensureLibraryPath` does guard against traversal outside the library root — `../`
  escapes and absolute paths elsewhere are rejected, and a string-prefix sibling (`<root>Evil/…`) is
  too. Now covered by tests; see #12 for the two edges of its symlink handling.
- `QuickLookController` correctly sets dataSource/delegate only inside `beginPreviewPanelControl:`
  (AGENTS.md pitfall #2).
- The blocking `DispatchSemaphore.wait()` calls in `CaptureSession` (lines 256-266, 274-283, 289-293)
  and `ExportService.write` work today because completions land on other queues. Fragile to reason
  about and a reason the capture path resists unit testing, but not actively broken — low priority.
