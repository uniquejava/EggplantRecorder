# AGENTS.md — EggplantRecorder (SwiftUI)

## What this is

macOS **15+** menu-bar screen recorder (OMI-like). **SwiftUI + AppKit**, not Wails.

Product requirements (source of truth for behaviour): [`docs/swiftui-rewrite.md`](docs/swiftui-rewrite.md).

**Status (2026-08-13):** MVP + **Record Area** on `main`. Next session = in-app Edit/export + OMI context stubs — **not** greenfield, **not** Area.

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
| Menu bar icon | `RecorderGlyph` template PDF — follow `EggplantFred/docs/menu-bar-icon.md` |
| Stable Debug `.app` | `build/EggplantRecorder.app` (see Commands) |

## Session continuity (start here)

1. Read this file + skim `docs/swiftui-rewrite.md` §2–§6 (flow + acceptance).
2. Prefer launching `build/EggplantRecorder.app` (rebuild recipe below). Avoid `/Applications/EggplantRecorder.app` (often stale / old Wails).
3. Capture semantics still mirror Wails ObjC: `EggplantRecorder-wails/internal/capture/` (especially pause timeline + dual audio). Area crop is native SCK `sourceRect` (Wails never had Area).
4. Do **not** reopen / extend the Wails app.
5. Commit only if asked (`usegmail` when they want that author).

### Suggested next work

| Priority | Item | Notes |
|----------|------|--------|
| High | In-app **Edit** (trim / export) | Spec §3.5; today Edit is disabled stub; Play opens default app |
| Medium | OMI context stubs | Convert/Compress, Rename, Remove from List — menu present, disabled |
| Low | Dock / app icon polish | See Wails `docs/app-icon.md` if needed |
| Low | ExportService / ffmpeg | Spec allows system ffmpeg; list duration uses `AVURLAsset` today |

## What’s implemented

- **Idle tray:** custom `NSStatusItem` + `RecorderGlyph` (not `MenuBarExtra` content — recording bar needs AppKit).
- **Menu:** Record Screen / Area / Window / Show Files List / Quit.
- **Area:** dim overlay + pale-blue **dashed** border + blue/white handles → embedded Cancel/Continue (same window, above canvas) → Options → `sourceRect` MP4 (`Area-…`). Initial rect = ~middle of usable screen (not “current window”).
- **Options bar:** bottom `NSPanel`, display/window picker (Area shows size label), System Sound + Microphone (+ device), Grant / Relaunch copy.
- **Capture:** ScreenCaptureKit screen/window/**area**, exclude self PID, system audio + mic as **separate** tracks, pause compresses timeline (no freeze frames).
- **Recording bar:** Pause / Stop / `HH:MM:SS` in status item.
- **Stop →** MP4 in library → Files List (800pt wide), thumbnails, Preview (Quick Look) + Play icons, OMI-ordered context menu.
- **Launch:** tray only — no Files List on cold start (reopen handler deferred).
- **Mic:** requires entitlement `com.apple.security.device.audio-input` under Hardened Runtime (without it TCC silently denies).

## Layout

```text
EggplantRecorder/
  EggplantRecorderApp.swift     # @main, accessory policy, hidden MenuBarExtra stub scene
  AppState.swift                # phase, elapsed timer, wires controllers (+ pendingArea)
  Recording/
    CaptureSession.swift        # SCStream + AVAssetWriter (Wails port + area sourceRect)
    CaptureSources.swift        # displays / windows / mics
    CapturePermissions.swift
    RecorderController.swift
  UI/
    StatusItem/                 # glyph + recording control bar
    OptionsBar/                 # bottom floating panel
    AreaSelection/              # dim overlay + embedded Continue bar
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

## Stack

| Layer | Tech |
|-------|------|
| Shell | `LSUIElement` + AppKit `NSStatusItem` |
| Panels / windows | `NSPanel` / `NSWindow` + `NSHosting*` |
| Capture | ScreenCaptureKit + AVAssetWriter (`sourceRect` for Area) |
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

**Tray → Screen/Window/Area → options → record → Files List is done.** Next valuable chunk is in-app Edit/export; keep OMI UX + Wails capture semantics; do not regress Area toolbar embedding, resize-by-delta, mic entitlement, or Quick Look controller rules.
