# AGENTS.md — EggplantRecorder (SwiftUI)

## What this is

macOS **15+** menu-bar screen recorder (OMI-like). **SwiftUI + AppKit**.

Product requirements: [`docs/product.md`](docs/product.md).

**Status (2026-08-15):** MVP + Area + Window hover-pick + solid options bar (FPS / Resolution / Countdown) + in-app Edit/trim/export on `main`. In-recording chrome (dashed frame + mini bar) now covers **Area and Window**. Known-issue backlog: [`docs/code-audit.md`](docs/code-audit.md).

## Identity

| | Value |
|--|-------|
| Display / `.app` | `EggplantRecorder` |
| Bundle ID | `click.yinsb.eggplantrecorder` |
| Team | `M5J7K9HVYB` (same as EggplantFred — stable Screen Recording TCC) |
| Min OS | macOS 15.0 |
| Library | `~/Movies/EggplantRecorder/` |
| GitHub | `https://github.com/uniquejava/EggplantRecorder` |
| UI reference | sibling `EggplantFred` (launcher/panels); OMI for product UX |
| Window pick reference | sibling `EggplantShot` (`WindowHitTester` / hover highlight) |
| Menu bar icon | `RecorderGlyph` template PDF — follow `EggplantFred/docs/menu-bar-icon.md` |
| Stable Debug `.app` | `build/Build/Products/Debug/EggplantRecorder.app` (see Commands) |

## Session continuity (start here)

1. Read this file + skim `docs/product.md` (flow + acceptance).
2. After code changes: **killall → xcodebuild `-derivedDataPath build` → open** `build/Build/Products/Debug/EggplantRecorder.app` (see Commands). Avoid `/Applications` and Xcode’s default DerivedData (often stale).
3. Capture: ScreenCaptureKit dual audio + pause timeline; Area = `sourceRect`; Window = CGWindowList hit-test → `window:ID`; Window Area = hit-test → Area preset. Options FPS / Resolution / Countdown apply at capture time.
4. Commit only if asked (`usegmail` when they want that author).

### Suggested next work

Audit backlog with verified `file:line` detail: [`docs/code-audit.md`](docs/code-audit.md) — start there.

| Priority | Item | Notes |
|----------|------|--------|
| **High** | Double-tap Stop / Record crash | `phase` / `isRecording` / `writing` all flip *after* the `await`, so a second tap re-enters and double-finishes the `AVAssetWriter` — audit #1 |
| Medium | Test target (none exists) | `CaptureTiming` PTS math, `ExportSettings`, `RecordingsLibrary` path guards are pure + untested — audit #2 |
| Medium | Serial duration probe in `RecordingsLibrary.list()` | Stalls Files List linearly with library size — audit #3 |
| Medium | OMI Convert/Compress | Menu present, disabled (`FilesListView`) — implement later |
| Low | Smaller audit cleanups | Dup UserDefaults key, filename-inferred kind, overlay boilerplate, dead `anchorRect`, force unwrap, sandbox bookmark — audit #4-9 |
| Low | Remaining options placeholders | PiP / Click Zoom / Keyboard / Timing Recording |
| Low | Dock / app icon polish | Done — `AppIcon.appiconset` + `scripts/generate_app_icons.py` (see `docs/app-icon.md`) |

## What’s implemented

- **Idle tray:** custom `NSStatusItem` + `RecorderGlyph`.
- **Menu:** Record Screen / Area / Window / Window Area / Show Files List / Preferences… / Quit.
- **Area:** dim overlay + pale-blue dashed border + handles → OMI options bar (selection stays) → Record → **in-recording** dashed frame + mini control bar below selection → `Area-….mp4`. Last area rect remembered (UserDefaults).
- **Window:** hover → blue dashed highlight → click → Options (no window dropdown). Esc cancels. In-recording: dashed frame + mini control bar that **follow the window** as it moves / resizes.
- **Window Area:** same hover-pick as Window, then continues as Area with the window frame as the preset selection (editable; capture is `sourceRect`, not `window:ID`).
- **Options bar:** bottom-center `NSPanel` (**16pt** above screen bottom), ~**224 / 224 / 76** × ~**186**, solid dark (no glass), draggable. Working: display picker (Screen), Mic, System Sound, cursor, **FPS / Resolution / Countdown**. PiP / Click Zoom / Keyboard / Timing Recording still placeholders. Grant / Relaunch copy when needed.
- **Capture:** screen/window/area, exclude self PID, dual audio tracks, pause compresses timeline.
- **Recording controls:** menu-bar Pause / Stop / `HH:MM:SS`; Area **and Window** also get the compact solid mini bar (Restart / Discard; Annotate stub).
- **Stop →** library MP4 → Files List (820pt), Quick Look + Play + Edit, OMI context menu.
- **Edit:** Files List right-click / Operation → preview + trim handles + Export → `Name-Edit.mp4` (dual audio preserved).
- **Preferences…** (⌘,): General (save folder, recording timer, after-record/edit actions, Dock hide, capture + export defaults) + About (Fred/Shot-style).
- **Launch:** tray only on cold start.
- **Mic:** entitlement `com.apple.security.device.audio-input` under Hardened Runtime.

## Layout

```text
EggplantRecorder/
  EggplantRecorderApp.swift
  AppState.swift                    # coordinator: phase + pendingArea / pendingWindow
  Models/
    RecordingKind.swift
    RecordingConfig.swift           # + CaptureFrameRate / Resolution / Countdown
    AppPreferences.swift            # Preferences → General (UserDefaults)
    ExportSettings.swift
  Recording/
    CaptureSession.swift            # SCK stream + AVAssetWriter lifecycle
    CaptureFilter.swift / CaptureAudio.swift / CaptureTiming.swift / CaptureError.swift
    CaptureSources.swift
    CapturePermissions.swift
    RecorderController.swift
    WindowHitTester.swift
  UI/
    Shared/                         # SelectionChrome, NSScreen+DisplayID, VisualEffectBackground
    StatusItem/                     # tray + RecordingControlBarView
    OptionsBar/                     # Controller, Model, View, Columns, Controls
    AreaSelection/                  # pick overlay + selection canvas
    RecordingChrome/                # in-recording chrome (dashed frame / mini bar) — Area + Window
    WindowSelection/                # hover-pick controller + overlay
    Countdown/                      # pre-record number overlay
    FilesList/                      # window + table + cells
    Editor/                         # trim preview + export window
    SettingsView.swift / AboutView.swift  # Preferences window
  Services/
    RecordingsLibrary.swift
    MediaProbe.swift
    ExportService.swift             # trim MP4; video re-encode, audio passthrough
    QuickLookController.swift
  Assets.xcassets/RecorderGlyph.imageset/
```

Xcode project uses **PBXFileSystemSynchronizedRootGroup** — new files under `EggplantRecorder/` are picked up automatically.

## Hard-won pitfalls (do not regress)

1. **Mic + Hardened Runtime:** need `com.apple.security.device.audio-input` or mic is silent with no prompt.
2. **Quick Look ≠ Preview.app:** `QLPreviewPanel`; set dataSource/delegate/index **only** inside `beginPreviewPanelControl:`.
3. **Cold launch must not open Files List:** defer `applicationShouldHandleReopen` with `readyForReopen`; no real `Settings`/`WindowGroup` at launch.
4. **Dual audio tracks:** never mux system + mic into one `AVAssetWriterInput`.
5. **Table tooltips:** SwiftUI `.help` often fails in `Table` — use AppKit `NSButton.toolTip`.
6. **Files List width:** **820** wide; keep column ideals tight.
7. **Area + options:** keep dim overlay while OptionsBar is up; panel level must be above the overlay so mic/Record stay clickable. Don’t name a property `toolbar` on `NSWindow` subclasses.
8. **Area handle resize:** drag **delta** from mouseDown, never “edge = mouse point”.
9. **Stale `/Applications` / default DerivedData:** prefer `build/Build/Products/Debug/EggplantRecorder.app` after agent builds.
10. **Options checkbox:** unchecked must stay hittable (`.contentShape` / non-clear fill).
11. **Options chrome:** solid fill (no outer SwiftUI padding / no glass halo). Open at `screen.frame.minY + 16`, bottom-centered.
12. **Window pick:** hover+click only; snapshot hit-tester before overlays; exclude own PID.
13. **Recording chrome (Area + Window):** border window must `ignoresMouseEvents`; mini panel is a separate higher-level panel so clicks reach Pause/Stop. Area excludes both via `excludePID`; Window capture is `desktopIndependentWindow`, so chrome can't leak into the MP4. Window chrome re-reads `WindowHitTester.liveFrame(of:)` each tick to follow the window — nil means gone/minimized, so drop the frame but keep the controls.

## Stack

| Layer | Tech |
|-------|------|
| Shell | `LSUIElement` + AppKit `NSStatusItem` |
| Panels | `NSPanel` / `NSWindow` + `NSHosting*` |
| Capture | ScreenCaptureKit + AVAssetWriter |
| Window pick | `CGWindowListCopyWindowInfo` → SCK `window:ID` |
| Options panel | Solid charcoal `NSPanel` (no visual-effect glass) |
| Preview | QuickLookUI |
| Edit / Export | AVFoundation reader/writer (trim; dual audio kept) |
| Library probe | AVFoundation |

## Commands

**Always** pass `-derivedDataPath build` (Shot-style) so the binary lands at a stable path. Without it, `xcodebuild` writes to `~/Library/Developer/Xcode/DerivedData/...` and you can launch a **stale** app.

Menu-bar apps keep the old process on a second `open` — **kill first**, then build, then open.

```bash
# Rebuild + relaunch (agents — always after code changes)
killall EggplantRecorder 2>/dev/null
xcodebuild -scheme EggplantRecorder -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/EggplantRecorder.app

open EggplantRecorder.xcodeproj
```

Do **not** open a different DerivedData path, and do **not** skip `-derivedDataPath build`.
`build/` is gitignored. Do **not** launch `/Applications/EggplantRecorder.app` (often stale — still has old `icons.icns`).

Stable path for docs / manual open: `build/Build/Products/Debug/EggplantRecorder.app` (also mirrored historically as `build/EggplantRecorder.app` when agents ditto’d; prefer the Products path above).

## One-liner for the next agent

**Tray → Screen / Area / Window / Window Area → options → record → Files List → Edit; Preferences… (General + About).** Next: Convert/Compress / PiP. Do not regress Area+options z-order, area recording chrome click-through, options checkbox hit-testing, bottom-16pt panel placement, mic entitlement, Quick Look rules, dual-audio export, or Preferences `openSettings` bridge.
