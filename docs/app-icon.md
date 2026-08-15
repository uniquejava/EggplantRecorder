# App icon (Dock / Finder / About)

Reference: [Apple HIG — App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)

## What we ship

| Rule | Value |
|------|--------|
| Master | `EggplantRecorder/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-master.png` |
| Art | **GenerateImage** → mask/resize only (`scripts/generate_app_icons.py`) |
| Shape | Continuous rounded rect, corner radius ≈ **22.37%** of edge |
| Corners | **Transparent** outside the rounded rect |
| Sizes | All `mac` idiom 16…512 @1x/@2x |
| Motif | Charcoal field + cream monitor + pale-blue screen + red record disc — **Recorder-only** |

```bash
python3 scripts/generate_app_icons.py
killall EggplantRecorder 2>/dev/null
xcodebuild -scheme EggplantRecorder -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/EggplantRecorder.app
```

About loads `NSImage(named: "AppIcon")` (with icns / workspace fallbacks) — see `UI/AboutView.swift`.

## Separate from menu bar

Menu bar uses template `RecorderGlyph` PDF. Do not use the Dock/About icon there.
