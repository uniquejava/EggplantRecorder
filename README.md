# EggplantRecorder

macOS 菜单栏录屏工具 · Menu-bar screen recorder for macOS **15+**

启动后只出现在菜单栏，不占 Dock。选全屏、区域或窗口，点录制，停下来就能在文件列表里预览、裁剪、导出。

Lives in the menu bar only (no Dock clutter). Record the full screen, a region, or a window — then preview, trim, and export from the Files List.

<p align="center">
  <img src="./docs/screenshot.png" alt="EggplantRecorder — Files List and options bar" width="720">
</p>

预构建安装包见 **[Releases](https://github.com/uniquejava/EggplantRecorder/releases)**（打 `v*` 标签会自动打包 DMG）。  
Prebuilt DMGs: **[Releases](https://github.com/uniquejava/EggplantRecorder/releases)** (`v*` tags build a DMG).

---

## 功能 · Features

| 中文 | English |
|------|---------|
| 全屏 / 区域 / 窗口 / 窗口区域 四种录制 | Screen / Area / Window / Window Area |
| 底部参数条：麦克风、系统声音、光标、帧率、分辨率、倒计时 | Options bar: mic, system audio, cursor, FPS, resolution, countdown |
| 录制中：暂停 / 停止 / 计时（暂停不计入时长） | While recording: Pause / Stop / timer (pause freezes the timeline) |
| 区域、窗口录制时带虚线框 + 迷你控制条 | Dashed frame + mini bar for Area and Window capture |
| 停录后打开文件列表：预览、播放、编辑裁剪 | Files List after stop: Quick Look, Play, Edit/trim |
| 系统声 + 麦克风双音轨，导出时保留 | Dual audio tracks (system + mic), kept on export |
| 界面中英双语（偏好设置 / 托盘可切换） | English + 简体中文 (Preferences / tray language picker) |

录像默认保存在 `~/Movies/EggplantRecorder/`。

---

## 系统要求 · Requirements

- macOS **15** 或更高 / macOS **15+**
- 首次使用需授权 **屏幕录制**；开麦时还需 **麦克风**  
  First launch needs **Screen Recording**; mic needs **Microphone** permission  
  （系统设置 → 隐私与安全性 / System Settings → Privacy & Security）

---

## 安装 · Install

1. 从 [Releases](https://github.com/uniquejava/EggplantRecorder/releases) 下载 `.dmg`，拖到「应用程序」  
   Download the `.dmg` from Releases and drag into Applications
2. 若 Gatekeeper 拦截：`xattr -cr /Applications/EggplantRecorder.app`
3. 打开应用 → 点菜单栏图标开始用  
   Open the app → click the menu bar icon

---

## 从源码运行 · Build from source

```bash
killall EggplantRecorder 2>/dev/null
xcodebuild -scheme EggplantRecorder -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/EggplantRecorder.app
```

或直接 `open EggplantRecorder.xcodeproj` 用 Xcode 运行。

> 请用上面的路径打开 Debug 包，不要用可能过期的 `/Applications/EggplantRecorder.app`。  
> Prefer the path above — `/Applications` may be a stale install.

---

## 文档 · Docs

| 文档 | 内容 |
|------|------|
| [docs/product.md](docs/product.md) | 产品流程与验收 / product flow |
| [AGENTS.md](AGENTS.md) | 开发交接、构建约定、已知坑 / agent handoff |
| [docs/app-icon.md](docs/app-icon.md) | App 图标说明 / app icon notes |

---

## 尚未完成 · Not yet

PiP 摄像头、点击放大、键盘叠加、定时开录、Convert / Compress 等仍为占位。  
PiP camera, click zoom, keyboard overlay, timed start, Convert/Compress — still stubs.

---

## License

见仓库内许可文件（若有）/ See repository license if present.
