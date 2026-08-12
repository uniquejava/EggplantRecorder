# EggplantRecorder

Native macOS **15+** menu-bar screen recorder (SwiftUI + AppKit).

Requirements / MVP: **[docs/swiftui-rewrite.md](docs/swiftui-rewrite.md)**.

Wails-era reference: sibling folder `EggplantRecorder-wails`.

## Open / build

```bash
open EggplantRecorder.xcodeproj
# or
xcodebuild -scheme EggplantRecorder -configuration Debug build
```

| | |
|--|--|
| Bundle ID | `click.yinsb.eggplantrecorder` |
| Team | `M5J7K9HVYB` |
| Library | `~/Movies/EggplantRecorder/` |

## Layout

```text
EggplantRecorder/
  AppState.swift
  Recording/          # ScreenCaptureKit session, sources, permissions
  UI/StatusItem/      # Idle glyph + recording Pause/Stop/timer
  UI/OptionsBar/      # Bottom floating config panel
  UI/FilesList/       # Post-stop library window
  Services/           # Library scan + duration probe
```

## Manual check

1. Menu bar glyph → Record Screen / Window → bottom options bar → Record.
2. Status item becomes Pause + Stop + `HH:MM:SS` (pause freezes the clock).
3. Stop → MP4 under `~/Movies/EggplantRecorder/` → Files List.
4. First run: grant Screen Recording (and Microphone if enabled); **relaunch** if sources stay empty.
