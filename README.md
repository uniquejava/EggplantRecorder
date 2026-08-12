# EggplantRecorder

Native macOS **15+** menu-bar screen recorder (SwiftUI + AppKit), OMI-inspired.

| | |
|--|--|
| Bundle ID | `click.yinsb.eggplantrecorder` |
| Team | `M5J7K9HVYB` |
| Library | `~/Movies/EggplantRecorder/` |
| Requirements | [docs/swiftui-rewrite.md](docs/swiftui-rewrite.md) |
| Agent handoff | [AGENTS.md](AGENTS.md) |
| Wails reference | sibling `EggplantRecorder-wails` (frozen) |

## Status

**On `main`:** tray-only launch; Record **Screen / Area / Window**; dual audio + pause; Files List with Quick Look + Play.

**Still open:** in-app Edit/trim; Convert/Compress / Rename / Remove from List.

## Open / build

```bash
open /Users/cyper/code/eggplant-projects/EggplantRecorder/build/EggplantRecorder.app
```

Rebuild + refresh that path:

```bash
cd /Users/cyper/code/eggplant-projects/EggplantRecorder
xcodebuild -scheme EggplantRecorder -configuration Debug -derivedDataPath "$PWD/build/DerivedData" build \
  && rm -rf build/EggplantRecorder.app \
  && ditto "$PWD/build/DerivedData/Build/Products/Debug/EggplantRecorder.app" build/EggplantRecorder.app \
  && open build/EggplantRecorder.app
```

Or: `open EggplantRecorder.xcodeproj`.

**Don’t use** `/Applications/EggplantRecorder.app` — often an older/stale build.

Scheme: `EggplantRecorder`. First Screen Recording / Microphone grant may need a **Relaunch** before sources appear.

## Layout

```text
EggplantRecorder/
  AppState.swift
  Recording/          # ScreenCaptureKit + writer (+ area sourceRect)
  UI/StatusItem/      # tray glyph + Pause/Stop/timer
  UI/OptionsBar/      # bottom config panel
  UI/AreaSelection/   # dim overlay + Continue bar
  UI/FilesList/       # library window (~800pt)
  Services/           # library, thumbnails, Quick Look
```

## Manual check

1. Cold start → **only** menu bar icon (no Files List).
2. Record Screen/Window → options bar → Record.
3. Record Area → pale-blue dashed selection + handles → Continue still clickable → options → Record → `Area-….mp4`.
4. Status item → Pause / Stop / clock (pause freezes elapsed + file timeline).
5. Stop → MP4 in `~/Movies/EggplantRecorder/` → Files List; Preview = Quick Look, Play = default app; double-click = Preview.
6. Right-click row → OMI-ordered menu (unimplemented items disabled).
