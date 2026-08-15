# EggplantRecorder

Native **macOS 15+** menu-bar screen recorder — pick screen, area, or window, then preview, trim, and export.

[简体中文](./README_zh.md)

Prebuilt DMGs are on **[Releases](https://github.com/uniquejava/EggplantRecorder/releases)** — push a `v*` tag to build one.

<p align="center">
  <img src="./docs/screenshot.png" alt="EggplantRecorder — Files List and options bar" width="720">
</p>

## Features

- **Four capture modes** — Screen / Area / Window / Window Area
- **Options bar** — microphone, system audio, cursor, FPS, resolution, countdown
- **While recording** — Pause / Stop / elapsed timer (pause freezes the timeline)
- **Area & Window chrome** — dashed frame + mini control bar that stays out of the file
- **Files List** — Quick Look, Play, Edit/trim after you stop
- **Dual audio** — system sound + mic as separate tracks, kept on export
- **English + 简体中文** — switch in Preferences or the tray menu (relaunch)

Recordings save to `~/Movies/EggplantRecorder/` by default.

## Requirements

- macOS **15** or later
- **Screen Recording** permission on first use; **Microphone** if you enable mic  
  (System Settings → Privacy & Security)

## Install

1. Download the `.dmg` from [Releases](https://github.com/uniquejava/EggplantRecorder/releases) and drag into Applications
2. If Gatekeeper blocks it: `xattr -cr /Applications/EggplantRecorder.app`
3. Open the app → click the menu bar icon

## Build from source

```bash
killall EggplantRecorder 2>/dev/null
xcodebuild -scheme EggplantRecorder -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/EggplantRecorder.app
```

Or `open EggplantRecorder.xcodeproj` and run from Xcode.

Prefer the Debug path above — `/Applications/EggplantRecorder.app` may be a stale install.

## Docs

| Doc | Contents |
|-----|----------|
| [docs/product.md](docs/product.md) | Product flow and acceptance |
| [AGENTS.md](AGENTS.md) | Agent handoff, build rules, pitfalls |
| [docs/app-icon.md](docs/app-icon.md) | App icon notes |

## Not yet

PiP camera, click zoom, keyboard overlay, timed start, Convert/Compress — still stubs.
