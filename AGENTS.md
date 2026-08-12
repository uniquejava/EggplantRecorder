# AGENTS.md — EggplantRecorder (SwiftUI)

## What this is

macOS **15+** menu-bar screen recorder (OMI-like). **SwiftUI + AppKit**, not Wails.

Full product requirements: [`docs/swiftui-rewrite.md`](docs/swiftui-rewrite.md).

## Identity

| | Value |
|--|-------|
| Display / `.app` | `EggplantRecorder` |
| Bundle ID | `click.yinsb.eggplantrecorder` |
| Team | `M5J7K9HVYB` (same as EggplantFred — stable Screen Recording TCC) |
| Wails archive | `/Users/cyper/code/eggplant-projects/EggplantRecorder-wails` |
| UI reference | `../EggplantFred` |

## Session continuity

1. Read `docs/swiftui-rewrite.md`.
2. Capture behaviour reference: `EggplantRecorder-wails/internal/capture/`.
3. Menu bar icon rules: `EggplantFred/docs/menu-bar-icon.md`.
4. Open `EggplantRecorder.xcodeproj` in Xcode; scheme `EggplantRecorder`.
5. Commit only if asked (`usegmail` when they want that author).

## Stack

| Layer | Tech |
|-------|------|
| UI | SwiftUI `MenuBarExtra` + AppKit panels |
| Capture | ScreenCaptureKit (port from Wails ObjC) |
| Export | system `ffmpeg` / `ffprobe` |
| Library | `~/Movies/EggplantRecorder/` |

## Commands

```bash
open EggplantRecorder.xcodeproj
# or
xcodebuild -scheme EggplantRecorder -configuration Debug build
```
