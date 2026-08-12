# AGENTS.md — EggplantRecorder (SwiftUI)

## What this is

macOS **15+** menu-bar screen recorder (OMI-like). **SwiftUI + AppKit**, not Wails.

Product requirements (source of truth for behaviour): [`docs/swiftui-rewrite.md`](docs/swiftui-rewrite.md).

**Status (2026-08-13):** MVP + Area + **OMI options bar** + **Window hover-pick** on `main`. Next session = in-app Edit/export — **not** greenfield, **not** options/window chrome.

## Identity

| | Value |
|--|-------|
| Display / `.app` | `EggplantRecorder` |
| Bundle ID | `click.yinsb.eggplantrecorder` |
| Team | `M5J7K9HVYB` (same as EggplantFred — stable Screen Recording TCC) |
| Min OS | macOS 15.0 |
| Library | `~/Movies/EggplantRecorder/` |
| Wails archive | `/Users/cyper/code/eggplant-projects/EggplantRecorder-wails` |
| UI reference | `../EggplantFred` (launcher/panels); OMI for product UX |
| Window pick reference | `../EggplantShot` (`WindowHitTester` / hover highlight) |
| Menu bar icon | `RecorderGlyph` template PDF — follow `EggplantFred/docs/menu-bar-icon.md` |
| Stable Debug `.app` | `build/EggplantRecorder.app` (see Commands) |

## Session continuity (start here)

1. Read this file + skim `docs/swiftui-rewrite.md` §2–§6 (flow + acceptance).
2. Prefer launching `build/EggplantRecorder.app` (rebuild recipe below). Avoid `/Applications/EggplantRecorder.app` (often stale / old Wails).
3. Capture semantics still mirror Wails ObjC: `EggplantRecorder-wails/internal/capture/` (especially pause timeline + dual audio). Area crop is native SCK `sourceRect`. Window pick uses CGWindowList hit-test → `window:ID` for SCK (EggplantShot-style).
4. Do **not** reopen / extend the Wails app.
5. Commit only if asked (`usegmail` when they want that author).

### Suggested next work

| Priority | Item | Notes |
|----------|------|--------|
| High | In-app **Edit** (trim / export) | Spec §3.5; today Edit is disabled stub; Play opens default app |
| Medium | OMI context stubs | Convert/Compress, Rename, Remove from List — menu present, disabled |
| Low | Wire options placeholders | PiP / Click Zoom / Keyboard / FPS / Resolution / Countdown |
| Low | Dock / app icon polish | See Wails `docs/app-icon.md` if needed |
| Low | ExportService / ffmpeg | Spec allows system ffmpeg; list duration uses `AVURLAsset` today |

## What’s implemented

- **Idle tray:** custom `NSStatusItem` + `RecorderGlyph` (not `MenuBarExtra` content — recording bar needs AppKit).
- **Menu:** Record Screen / Area / Window / Show Files List / Quit.
- **Area:** dim overlay + pale-blue **dashed** border + blue/white handles → embedded Cancel/Continue (same window, above canvas) → Options → `sourceRect` MP4 (`Area-…`).
- **Window:** hover → blue dashed highlight on window under cursor → click → Options (no window dropdown). Hit-test via `WindowHitTester` (from EggplantShot, plus `windowID`). Esc cancels.
- **Options bar (OMI-like):** bottom-center `NSPanel` (**16pt** above physical screen bottom), ~**260 / 260 / 100** columns × ~**230** tall, `NSVisualEffectView` glass, large red record button, draggable (`WindowDragGesture` + `isMovableByWindowBackground`). Working: display picker (Screen), Mic (+ device menu), System Sound, Capture Mouse Cursor (`showsCursor`). Placeholders (disabled): PiP, Click Zoom, Keyboard, Frame Rate, Resolution, Timing, Count Down. Window mode hides source row. Grant / Relaunch copy when needed.
- **Capture:** ScreenCaptureKit screen/window/**area**, exclude self PID, system audio + mic as **separate** tracks, pause compresses timeline (no freeze frames).
- **Recording bar:** Pause / Stop / `HH:MM:SS` in status item.
- **Stop →** MP4 in library → Files List (800pt wide), thumbnails, Preview (Quick Look) + Play icons, OMI-ordered context menu.
- **Launch:** tray only — no Files List on cold start (reopen handler deferred).
- **Mic:** requires entitlement `com.apple.security.device.audio-input` under Hardened Runtime (without it TCC silently denies).

## Layout

```text
EggplantRecorder/
  EggplantRecorderApp.swift     # @main, accessory policy, hidden MenuBarExtra stub scene
  AppState.swift                # phase, elapsed timer, wires controllers (+ pendingArea / pendingWindow)
  Recording/
    CaptureSession.swift        # SCStream + AVAssetWriter (Wails port + area sourceRect)
    CaptureSources.swift        # displays / windows / mics
    CapturePermissions.swift
    RecorderController.swift
    WindowHitTester.swift       # CGWindowList front-to-back pick (EggplantShot port + windowID)
  UI/
    StatusItem/                 # glyph + recording control bar
    OptionsBar/                 # OMI glass panel (260/260/100)
    AreaSelection/              # dim overlay + embedded Continue bar
    WindowSelection/            # hover dashed border → click to confirm
    FilesList/                  # library window (SwiftUI Table + AppKit chrome)
  Services/
    RecordingsLibrary.swift     # Screen- / Window- / Area- prefixes
    MediaProbe.swift            # duration + thumbnails
    QuickLookController.swift   # QLPreviewPanel (Finder Spacebar), responder-chain correct
  Assets.xcassets/RecorderGlyph.imageset/
```

Xcode project uses **PBXFileSystemSynchronizedRootGroup** — new files under `EggplantRecorder/` are picked up automatically (`Info.plist` / entitlements excluded from Copy Bundle Resources).

## Hard-won pitfalls (do not regress)

1. **Mic + Hardened Runtime:** must ship `com.apple.security.device.audio-input` or mic is silent with no prompt.
2. **Quick Look ≠ Preview.app:** use `QLPreviewPanel`; set `dataSource`/`delegate`/`currentPreviewItemIndex` **only** inside `beginPreviewPanelControl:` (see `QLPreviewPanel.h`). Controller lives on `NSApp` responder chain via `QuickLookController`.
3. **Cold launch must not open Files List:** `applicationShouldHandleReopen` is deferred with `readyForReopen`; avoid real `Settings`/`WindowGroup` scenes that materialize windows. Status UI is AppKit `NSStatusItem`.
4. **Dual audio tracks:** never mux system + mic into one `AVAssetWriterInput`.
5. **Table tooltips:** SwiftUI `.help` often fails in `Table` cells — Operation buttons use AppKit `NSButton.toolTip`.
6. **Files List width:** content window **800** wide; keep column ideals tight or H-scrollbar returns.
7. **Area Confirm bar:** must live **inside** the overlay window (sibling above canvas). A separate floating panel gets clicks stolen by the full-screen mask. Do not rename window property `toolbar` — conflicts with `NSWindow.toolbar`.
8. **Area handle resize:** resize by **drag delta** from mouseDown, never “edge = mouse point” — the latter collapses height/width to ~0 on first tick then `minSize` (40) snaps.
9. **Stale `/Applications`:** prefer `build/EggplantRecorder.app` after agent builds; Dock/Applications may open an old binary that looks “unchanged”.
10. **Options checkbox hit-testing:** unchecked boxes must not use fully transparent fill — add `.contentShape(Rectangle())` / near-opaque clear fill or only “uncheck” works.
11. **Options panel chrome:** no outer SwiftUI `.padding` around the glass (looks like a gray halo). Open at **screen.frame.minY + 16**, bottom-centered — do not auto-anchor under the picked window.
12. **Window pick vs Area:** Window is hover+click only (no free drag refine). Snapshot `WindowHitTester` before overlays cover the screen; exclude own PID.

## Stack

| Layer | Tech |
|-------|------|
| Shell | `LSUIElement` + AppKit `NSStatusItem` |
| Panels / windows | `NSPanel` / `NSWindow` + `NSHosting*` |
| Capture | ScreenCaptureKit + AVAssetWriter (`sourceRect` for Area) |
| Window pick | `CGWindowListCopyWindowInfo` → SCK `window:ID` |
| Options glass | `NSVisualEffectView` (`.hudWindow`) |
| Preview | QuickLookUI (`QLPreviewPanel`) |
| Library probe | AVFoundation (not ffmpeg yet) |

## Commands

```bash
# Stable run path (after build recipe below)
open /Users/cyper/code/eggplant-projects/EggplantRecorder/build/EggplantRecorder.app

# Rebuild + install into build/ + launch
cd /Users/cyper/code/eggplant-projects/EggplantRecorder
xcodebuild -scheme EggplantRecorder -configuration Debug -derivedDataPath "$PWD/build/DerivedData" build \
  && rm -rf build/EggplantRecorder.app \
  && ditto "$PWD/build/DerivedData/Build/Products/Debug/EggplantRecorder.app" build/EggplantRecorder.app \
  && open build/EggplantRecorder.app

# Or Xcode UI
open EggplantRecorder.xcodeproj
```

`build/` is gitignored. Proxy (China) if network fails: `127.0.0.1:7897` — don’t enable preemptively.

## One-liner for the next agent

**Tray → Screen / Area / Window(hover-pick) → OMI options → record → Files List is done.** Next valuable chunk is in-app Edit/export; keep OMI UX + Wails capture semantics; do not regress Area toolbar embedding, options checkbox hit-testing, bottom-16pt panel placement, mic entitlement, or Quick Look controller rules.
