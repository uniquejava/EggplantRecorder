# Code audit — 2026-08-15

Findings from an audit of the Cursor-built codebase. Every item below was **verified against
the source**, not inferred. Ordered by value; `file:line` refers to the tree at commit after
"Follow the recorded window with the mini panel".

Fix items top-down. Tick them off here as they land so the next session doesn't re-audit.

---

## 1. Double-tap Stop / Record can crash or orphan a capture — HIGH

**Status:** open. Only item here that can lose a user's recording.

`AppState.stopRecording()` guards `phase == .recording`; `RecorderController.stop()`
(`Recording/RecorderController.swift:46`) guards `isRecording`. Both flags flip **after**
`await recorder.stop()` resolves, and no button disables itself meanwhile
(`UI/RecordingChrome/RecordingMiniPanel.swift` `onStop`, `UI/StatusItem/RecordingControlBarView.swift`),
so a second tap during the await window re-enters through the same guard.

`CaptureSession.stopAndFinish()` (`Recording/CaptureSession.swift:269`) has no re-entry guard and
never nils `writer`, so the second pass calls `markAsFinished()` and `finishWriting` on an
already-completed `AVAssetWriter`. That raises an ObjC exception, which Swift `try/catch` cannot
intercept → hard crash.

Same shape on start: `CaptureSession.start()` checks `if writing` at line 54, but `writing` isn't
set `true` until `beginWriting()` runs (line 266), and there are `await` points in between
(`SCShareableContent.excludingDesktopWindows`, mic permission). A double Record tap can build two
`SCStream`s + `AVAssetWriter`s against the same output path and orphan the first (never stopped).

**Fix:** add transitional `.starting` / `.stopping` cases to `AppPhase`, set synchronously *before*
the first `await`; guard every entry point (`startRecording`, `stopRecording`, `cancelRecording`,
`restartRecording`) on them; disable Record / Stop / Restart / Cancel for the duration. Make
`stopAndFinish()` idempotent as a belt-and-braces second layer.

## 2. No test target exists

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
