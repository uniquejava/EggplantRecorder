# EggplantRecorder

Native macOS **15+** menu-bar screen recorder (SwiftUI + AppKit), OMI-inspired.

| | |
|--|--|
| Bundle ID | `click.yinsb.eggplantrecorder` |
| Team | `M5J7K9HVYB` |
| Library | `~/Movies/EggplantRecorder/` |
| Requirements | [docs/product.md](docs/product.md) |
| Agent handoff | [AGENTS.md](AGENTS.md) |
| GitHub | https://github.com/uniquejava/EggplantRecorder |

## Status

**On `main`:** tray-only launch; Record **Screen / Area / Window** (Window = hover → click); OMI-like glass options bar; dual audio + cursor toggle + pause; Files List with Quick Look + Play.

**Still open:** in-app Edit/trim; Convert/Compress / Rename / Remove from List; options placeholders (PiP, FPS, …).

## Open / build

```bash
open build/EggplantRecorder.app
```

Rebuild + refresh that path:

```bash
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
  Recording/            # ScreenCaptureKit + writer (+ area, WindowHitTester)
  UI/StatusItem/        # tray glyph + Pause/Stop/timer
  UI/OptionsBar/        # OMI glass panel (260/260/100, bottom +16pt)
  UI/AreaSelection/     # dim overlay + Continue bar
  UI/WindowSelection/   # hover window highlight → click
  UI/FilesList/         # library window (~800pt)
  Services/             # library, thumbnails, Quick Look
```

## Manual check

1. Cold start → **only** menu bar icon (no Files List).
2. Record Screen → options bar at bottom center (~16pt up) → Record.
3. Record Area → pale-blue dashed selection + handles + OMI options bar → Record → `Area-….mp4`.
4. Record Window → hover blue dashed border → click → options (no window dropdown) → Record → `Window-….mp4`.
5. Status item → Pause / Stop / clock (pause freezes elapsed + file timeline).
6. Stop → MP4 in `~/Movies/EggplantRecorder/` → Files List; Preview = Quick Look, Play = default app.
7. Right-click row → OMI-ordered menu (unimplemented items disabled).
