# Code audit — 2026-08-15

Findings from an audit of the Cursor-built codebase. Every item below was **verified against
the source**, not inferred. Ordered by value; `file:line` refers to the tree at commit after
"Follow the recorded window with the mini panel".

Fix items top-down. Tick them off here as they land so the next session doesn't re-audit.

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

**Status:** open — and now the top item. The audit #1 fix is a state machine that nothing exercises.

`grep productType EggplantRecorder.xcodeproj/project.pbxproj` → one `application` target, nothing else.

These are pure, deterministic, and currently unexercised:

- `Recording/CaptureTiming.swift` — pause/resume PTS math (pitfall #4 / #8 territory)
- `Models/ExportSettings.swift` — `outputSize`, `videoBitrate`, `estimatedBytes`
- `Services/RecordingsLibrary.swift` — `sanitizeBaseName`, `makeEditOutputURL`, the
  `ensureLibraryPath` path-traversal guard
- `UI/AreaSelection/AreaSelectionCanvas.swift` — `resizedByDelta` / `clamp` geometry

The "Hard-won pitfalls" list in AGENTS.md is effectively a hand-maintained regression suite; a small
XCTest target would make it enforceable.

## 3. `RecordingsLibrary.list()` probes durations serially

`Services/RecordingsLibrary.swift:56-86` — `for url in urls { … await MediaProbe.duration(of: url) … }`
awaits one `AVURLAsset.load(.duration)` at a time. Runs after every recording, every Files List open,
and every edit, so the stall grows linearly with library size. Use a task group and reassemble in order.

## 4. Library-path UserDefaults key is typed twice

`Models/AppPreferences.swift:16` and `Services/RecordingsLibrary.swift:34` each hold their own copy of
`"click.yinsb.eggplantrecorder.libraryFolderPath"`, plus their own copy of the
trim-and-fall-back-to-`~/Movies/EggplantRecorder` logic (`AppPreferences.swift:90-96` vs
`RecordingsLibrary.swift:36-43`). They agree today; nothing enforces it, and a desync silently splits
where files are written from where Preferences says they go.

`RecordingsLibrary` reads `UserDefaults` directly because it runs off the main actor — that's a fair
reason not to call `AppPreferences.shared`, but the key + fallback logic should still be one
non-actor-isolated helper.

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

`UI/AreaSelection/AreaSelectionCanvas.swift:134` — `selectionAtDragStart = selectionInWindowCoords!`
force-unwraps a property assigned on the line above. Safe today, a crash after any reorder. Reuse the
RHS directly. It's the only force unwrap in an otherwise `guard let`-disciplined codebase.

## 9. Sandbox forward-risk: raw path for the user-chosen save folder

`EggplantRecorder.entitlements` sets `com.apple.security.app-sandbox = false`, and
`AppPreferences.chooseLibraryFolder()` (`Models/AppPreferences.swift:112-124`) stores a plain
`url.path`. Fine now; breaks on first relaunch if sandboxing is ever enabled (App Store, hardening
pass) because a raw path carries no access grant — it needs a security-scoped bookmark
(`bookmarkData(options: .withSecurityScope)` + `startAccessingSecurityScopedResource()`). Cheap to
bake in now, painful once users have old-format UserDefaults to migrate.

---

## Noted as fine (don't re-flag)

- `CaptureSession` sample delivery is correctly serialized — `pause()` / `resume()` and
  `stream(_:didOutputSampleBuffer:)` all run on the same private `queue` passed as
  `sampleHandlerQueue`, so there's no data race despite the class not being `@MainActor`.
- `RecordingsLibrary.ensureLibraryPath` does guard against traversal outside the library root,
  including a `resolvingSymlinksInPath()` fallback.
- `QuickLookController` correctly sets dataSource/delegate only inside `beginPreviewPanelControl:`
  (AGENTS.md pitfall #2).
- The blocking `DispatchSemaphore.wait()` calls in `CaptureSession` (lines 256-266, 274-283, 289-293)
  and `ExportService.write` work today because completions land on other queues. Fragile to reason
  about and a reason the capture path resists unit testing, but not actively broken — low priority.
