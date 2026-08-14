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

**On `main`:** tray-only launch; Record **Screen / Area / Window / Window Area**; solid dark options bar; dual audio + cursor toggle + pause; Files List with Quick Look + Play + **Edit** (trim / Export).

**Still open:** Convert/Compress / Remove from List; options placeholders (PiP, FPS, …).

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
  AppState.swift            # flow coordinator
  Models/                   # RecordingKind, RecordingConfig
  Recording/                # ScreenCaptureKit + writer, filter/audio/timing
  UI/Shared/                # dashed chrome, displayID, glass backdrop
  UI/StatusItem/            # tray glyph + Pause/Stop/timer
  UI/OptionsBar/            # solid dark panel (224/224/76, bottom +16pt)
  UI/AreaSelection/         # dim overlay + handles; in-recording dashed frame + mini bar
  UI/WindowSelection/       # hover window highlight → click
  UI/FilesList/             # library window (~820pt)
  UI/Editor/                # trim preview + export
  Services/                 # library, thumbnails, Quick Look, trim export
```

Code map for agents: [AGENTS.md](AGENTS.md). Product behavior: [docs/product.md](docs/product.md).
## Manual check

1. Cold start → **only** menu bar icon (no Files List).
2. Record Screen → options bar at bottom center (~16pt up) → Record.
3. Record Area → pale-blue dashed selection + handles + OMI options bar → Record → `Area-….mp4`.
4. Record Window → hover blue dashed border → click → options (no window dropdown) → Record → `Window-….mp4`.
5. Status item → Pause / Stop / clock (pause freezes elapsed + file timeline).
6. Stop → MP4 in `~/Movies/EggplantRecorder/` → Files List; Preview = Quick Look, Play = default app.
7. Right-click row → OMI-ordered menu; **Edit** opens trim + Export (`Name-Edit.mp4`).
