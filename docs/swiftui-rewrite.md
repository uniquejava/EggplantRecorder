# EggplantRecorder — SwiftUI 重做需求（交接用）

> 目的：在新会话 / 新工程里按本文实现，不再沿用 Wails。  
> **Wails 冻结备份：** `/Users/cyper/code/eggplant-projects/EggplantRecorder-wails`（含 git 历史；见该目录 `ARCHIVE.md`）。  
> 参考实现（行为与 capture 细节）：上述备份 / 本仓库 Wails 代码。  
> UI / 菜单栏范式：兄弟项目 `EggplantFred`（SwiftUI + AppKit）。  
> 产品灵感：本机安装的 **Screen Recorder by Omi**（托盘菜单 + 底部参数条 + 录制中控制条 + Files List）。

---

## 1. 结论与范围

### 做什么

用 **原生 macOS（SwiftUI + 必要 AppKit）** 重做 EggplantRecorder：

- 启动后 **仅菜单栏图标**（`LSUIElement` / MenuBarExtra，无 Dock 大窗）
- 托盘菜单启动录制；底部浮层选参数；录制中菜单栏变成控制条；停录后 Files List；可选 Edit

### 不做什么（本轮 / MVP）

- 区域录制（菜单项可占位 “Coming soon”）
- PiP 摄像头、Click Zoom、键盘捕获、倒计时、帧率/分辨率精细调节
- Convert/Compress、Rename、VIP 等 OMI 扩展功能
- 继续在 Wails 上堆功能（Wails 版仅作参考，可冻结）

### 身份（保持不变）

| | Value |
|--|-------|
| 产品名 / `.app` | `EggplantRecorder` |
| Bundle ID | `click.yinsb.eggplantrecorder` |
| GitHub（若沿用） | `https://github.com/uniquejava/eggplant-recorder` |
| 最低系统 | **macOS 15+**（ScreenCaptureKit mic API 等） |
| 开发签名 | 与 Fred 一样用稳定 **Apple Development Team**，避免每次 rebuild 重授 Screen Recording |

建议新工程路径：本目录 `/Users/cyper/code/eggplant-projects/EggplantRecorder`（SwiftUI）。  
Wails 冻结备份：`/Users/cyper/code/eggplant-projects/EggplantRecorder-wails`。  
**不要**复活 `video-editor-wails` / `com.cyper.*`。

---

## 2. 用户流程（必须对齐）

```text
启动 → 仅菜单栏图标
  ├─ 点击图标 → 弹出菜单
  │    ├─ Record Screen（全屏）
  │    ├─ Record Area（禁用 / Coming soon）
  │    ├─ Record Window（窗口）
  │    ├─ Show Files List
  │    └─ Quit
  │
  ├─ 选 Screen / Window → 屏幕底部弹出「参数条」
  │    ├─ 选显示器或窗口
  │    ├─ System Sound / Microphone（+ 输入设备）
  │    └─ 红色 Record 按钮 → 开始录制，参数条关闭
  │
  ├─ 录制中 → 菜单栏变为控制条（见 §3.2）
  │    ├─ Pause / Resume
  │    ├─ Stop
  │    └─ 已录时长 HH:MM:SS（不含暂停墙钟）
  │
  └─ Stop → MP4 已写入库目录 → 弹出 Files List
       ├─ Play / Preview / Show in Finder / Delete
       └─ Edit → 轻量裁剪 / Export（可第二阶段做全）
```

---

## 3. UI 规格

### 3.1 空闲托盘图标

- **Template image**（黑 + alpha），遵循 Fred 的菜单栏规范：见 `EggplantFred/docs/menu-bar-icon.md`
  - 光学约 **16pt** 高；不要又大又圆的实心圈
  - 建议图形：小监视器 / 录制点 + 简洁外形（与 Dock 图标可同源简化）
- 左键 / 右键：打开同一功能菜单（macOS 常规）
- 空闲时 **不要** 显示 “Idle” 长文案；图标即可（录制中见下）

### 3.2 录制中菜单栏控制条（对标 OMI）

录制开始后，菜单栏区域变成紧凑控制条，至少包含：

| 控件 | 行为 |
|------|------|
| Pause / Resume | 圆形按钮；暂停时图标切换 |
| Stop | 红方块停止 |
| Timer | `HH:MM:SS`，仅累计「在录」时间（pause 不推进） |

可选占位（可先禁用）：批注 / 画笔按钮。

实现提示：

- 优先 **自定义 `NSStatusItem` 视图** 或 SwiftUI `MenuBarExtra` 在 recording 态切换内容
- 不要只用纯文字 `● 0:12` 凑合（那是 Wails 临时方案）

### 3.3 底部参数条（对标 OMI 深色浮层）

- 屏幕 **底部居中**、始终置顶、圆角深色面板、关闭按钮
- 字段（精简版即可）：
  - Screen 模式：显示器下拉（多屏时）
  - Window 模式：窗口下拉（标题；缩略图可选）
  - System Sound 开关
  - Microphone 开关 + 设备下拉
  - 右侧大红色 Record
- **权限态要说人话**：
  - 无 Screen Recording → Grant access / Open Settings + 短说明
  - Preflight 已开但列表空 → **Relaunch**（托盘保活，关窗不够）

### 3.4 Files List（停录后主界面）

- 停录 **不要** 直接进 Editor；先出列表（OMI “Files List”）
- 文件已是成品 **MP4**（见 §4）
- 列：Name、Duration、Size、Type（Screen/Window）、Date、Operation
- 行操作 / 右键：Preview/Play、Edit、Show in Finder、Delete  
  （本轮不做 Convert/Compress、Rename）
- 托盘菜单 **Show Files List** 随时打开此窗

### 3.5 Edit（可 MVP 简化）

- 从列表进入：预览 + 简单 trim/split/delete clip + Export MP4
- Wails 版已有逻辑可参考：`frontend/src/App.tsx` editor、`recorderservice.go` Export（ffmpeg）
- 若时间紧：Edit 可先 = 用 QuickTime / 系统播放 + “Reveal in Finder”，但需求上仍希望保留应用内裁剪

---

## 4. 录制与文件

### 4.1 库目录

- 默认：`~/Movies/EggplantRecorder/`
- 文件名：`Screen-YYYY-MM-DD-HHMMSS.mp4` / `Window-…`
- 停录即落盘，无需另存对话框

### 4.2 Capture（必须保留的产品行为）

参考现仓库 `internal/capture/`（ObjC）与 `docs/04-screencapturekit.md`：

1. **macOS only**，ScreenCaptureKit
2. 录显示器时 **排除本 app 窗口**（`excludePID = 本进程`）
3. System audio 与 Microphone 为 **两条独立音轨**（不要 mux 进同一个 `AVAssetWriterInput`）
4. Mic：`SCStreamConfiguration.microphoneCaptureDeviceID`；开录前申请 Microphone TCC
5. **Pause**：跳过写 sample，压缩时间线（无冻帧）；elapsed 不含暂停墙钟
6. 列表源：先列标题，缩略图异步（勿在主路径同步截全量窗口图卡死）
7. 导出 / 探测：可用系统 `ffmpeg` / `ffprobe`（注意 GUI app PATH）

现有 ObjC 可 **移植进 Swift 工程**（桥接头或逐步 Swift 化），不要从零猜行为。

### 4.3 权限文案

`Info.plist` 保留 Screen Recording / Microphone 用途说明（可从现 `build/darwin/Info*.plist` 抄）。

---

## 5. 工程与参考代码

### 新工程建议结构（对齐 Fred）

```text
EggplantRecorder/
  EggplantRecorderApp.swift          # @main, MenuBarExtra, LSUIElement
  Recording/
    CaptureSession.swift             # 从 internal/capture 迁
    RecorderController.swift         # start/pause/resume/stop
  UI/
    StatusItem/                      # 空闲图标 + 录制中控制条
    OptionsBarView.swift             # 底部参数条 NSPanel
    FilesListView.swift
    EditorView.swift                 # 可二期
  Services/
    RecordingsLibrary.swift          # ~/Movies/EggplantRecorder 扫描
    ExportService.swift              # ffmpeg
  Assets.xcassets                    # 菜单栏 template + Dock icon
```

### 旧 Wails 仓库里值得抄的

| 主题 | 位置 |
|------|------|
| Capture 实现 | `internal/capture/*.m` + `capture_darwin.h` |
| Pause 时间线语义 | `capture_recorder.m` |
| 权限坑 | `docs/03-macos-permissions.md`、`AGENTS.md` Hard rules |
| 库 / 列表 API 雏形 | `recorderservice.go`（ListRecordings / Delete / Reveal / OpenForEdit） |
| 托盘菜单文案与流程 | 本文 §2 + 当前 `tray.go` / `ui.go` |
| Dock 图标 | `docs/app-icon.md`、`build/appicon.png` |
| Fred 菜单栏图标规范 | `../EggplantFred/docs/menu-bar-icon.md` |

### 网络（中国）

代理通常 `127.0.0.1:7897`（见根 `AGENTS.md`）。

---

## 6. 验收清单

1. 冷启动：Dock 无常驻大窗，只有菜单栏图标；图标不是粗糙实心大圆。
2. 菜单：Screen / Area(禁用) / Window / Files List / Quit。
3. Screen/Window → 底部参数条 → Record → 参数条消失。
4. 录制中：菜单栏为 Pause + Stop + 计时；Pause 后计时停、文件时间线无冻帧。
5. Stop → `~/Movies/EggplantRecorder/` 出现 MP4 → Files List 打开并高亮新文件。
6. Edit / Finder / Delete / Play 可用（Edit 深度按 §3.5）。
7. 无权限 / 需 Relaunch 时文案正确，不会只显示神秘 “No sources”。
8. 录屏时不把本 app 的 Files List / 参数条录进去（exclude self）。

---

## 7. 实施顺序（建议新会话按此拆）

1. Xcode 工程 + Bundle ID + 权限 plist + 空 MenuBarExtra（好图标）
2. 移植 ScreenCaptureKit 录屏（屏/窗 + 双音轨 + pause）
3. 底部 Options 面板 + 权限态
4. 录制中 Status Item 控制条
5. 库目录 + Files List
6. Edit / Export（可并行或二期）
7. 稳定 codesign / 文档；冻结或归档 Wails 版说明

---

## 8. 给下一任 Agent 的一句话

**不要继续扩 Wails。** 按本文在 SwiftUI 里重做托盘优先录屏器；行为以 OMI 交互 + 本仓库 `internal/capture` 语义为准；UI 范式抄 EggplantFred。
