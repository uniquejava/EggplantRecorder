# AGENTS.md — EggplantRecorder (SwiftUI)

## What this is

macOS **15+** menu-bar screen recorder (OMI-like). **SwiftUI + AppKit**.

Product requirements: [`docs/product.md`](docs/product.md).

**Status (2026-08-14):** MVP + Area + Window hover-pick + solid options bar + in-app Edit/trim/export on `main`.

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
| Stable Debug `.app` | `build/EggplantRecorder.app` (see Commands) |

## Session continuity (start here)

1. Read this file + skim `docs/product.md` (flow + acceptance).
2. After code changes: **killall → xcodebuild → open** `build/EggplantRecorder.app` (see Commands). Avoid `/Applications/EggplantRecorder.app` (often stale).
3. Capture: ScreenCaptureKit dual audio + pause timeline; Area = `sourceRect`; Window = CGWindowList hit-test → `window:ID`; Window Area = hit-test → Area preset.
4. Commit only if asked (`usegmail` when they want that author).

### Suggested next work

| Priority | Item | Notes |
|----------|------|--------|
| Medium | OMI context stubs | Convert/Compress, Remove from List — menu present, disabled (`FilesListView`) |
| Low | Wire options placeholders | PiP / Click Zoom / Keyboard / FPS / Resolution / Countdown → `OptionsBarColumns` + `OptionsBarModel` |
| Low | Dock / app icon polish | |

## What’s implemented

- **Idle tray:** custom `NSStatusItem` + `RecorderGlyph`.
- **Menu:** Record Screen / Area / Window / Window Area / Show Files List / Quit.
- **Area:** dim overlay + pale-blue dashed border + handles → OMI options bar (selection stays) → Record → **in-recording** dashed frame + mini control bar below selection → `Area-….mp4`. Last area rect remembered (UserDefaults).
- **Window:** hover → blue dashed highlight → click → Options (no window dropdown). Esc cancels.
- **Window Area:** same hover-pick as Window, then continues as Area with the window frame as the preset selection (editable; capture is `sourceRect`, not `window:ID`).
- **Options bar:** bottom-center `NSPanel` (**16pt** above screen bottom), ~**224 / 224 / 76** × ~**186**, solid dark (no glass), draggable. Working: display picker (Screen), Mic, System Sound, cursor. Placeholders disabled. Grant / Relaunch copy when needed.
- **Capture:** screen/window/area, exclude self PID, dual audio tracks, pause compresses timeline.
- **Recording controls:** menu-bar Pause / Stop / `HH:MM:SS`; Area also gets compact solid mini bar (Restart / Discard; Annotate stub).
- **Stop →** library MP4 → Files List (820pt), Quick Look + Play + Edit, OMI context menu.
- **Edit:** Files List right-click / Operation → preview + trim handles + Export → `Name-Edit.mp4` (dual audio preserved).
- **Launch:** tray only on cold start.
- **Mic:** entitlement `com.apple.security.device.audio-input` under Hardened Runtime.

## Layout

```text
EggplantRecorder/
  EggplantRecorderApp.swift
  AppState.swift                    # coordinator: phase + pendingArea / pendingWindow
  Models/
    RecordingKind.swift
    RecordingConfig.swift
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
    AreaSelection/                  # pick overlay + in-recording chrome (border / mini bar)
    WindowSelection/                # hover-pick controller + overlay
    FilesList/                      # window + table + cells
    Editor/                         # trim preview + export window
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
9. **Stale `/Applications`:** prefer `build/EggplantRecorder.app` after agent builds.
10. **Options checkbox:** unchecked must stay hittable (`.contentShape` / non-clear fill).
11. **Options chrome:** solid fill (no outer SwiftUI padding / no glass halo). Open at `screen.frame.minY + 16`, bottom-centered.
12. **Window pick:** hover+click only; snapshot hit-tester before overlays; exclude own PID.
13. **Area recording chrome:** border window must `ignoresMouseEvents`; mini panel is a separate higher-level panel so clicks reach Pause/Stop. Both excluded from capture via `excludePID`.

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

Menu-bar apps keep the old process on a second `open` — **kill first**, then build, then open. Do **not** `open` without quitting; that just focuses the stale process.

```bash
# Rebuild + install into build/ + relaunch (agents — always after code changes)
killall EggplantRecorder 2>/dev/null
xcodebuild -scheme EggplantRecorder -configuration Debug -derivedDataPath "$PWD/build/DerivedData" build \
  && rm -rf build/EggplantRecorder.app \
  && ditto "$PWD/build/DerivedData/Build/Products/Debug/EggplantRecorder.app" build/EggplantRecorder.app \
  && open build/EggplantRecorder.app

open EggplantRecorder.xcodeproj
```

`build/` is gitignored. Do **not** launch `/Applications/EggplantRecorder.app` (often stale).

## One-liner for the next agent

**Tray → Screen / Area(live selection + options → dashed frame + mini bar while recording) / Window(hover-pick) / Window Area(hover-pick → Area preset) → OMI options → record → Files List → right-click Edit (trim + Export) is done.** Next: Convert/Compress stubs / options placeholders. Do not regress Area+options z-order, area recording chrome click-through, options checkbox hit-testing, bottom-16pt panel placement, mic entitlement, Quick Look rules, or dual-audio export.
