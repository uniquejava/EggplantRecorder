# EggplantRecorder — 产品需求

> Native macOS **15+** menu-bar screen recorder（SwiftUI + AppKit）。  
> UI 参考：兄弟项目 `EggplantFred`；产品灵感：**Screen Recorder by Omi**。  
> Agent 交接以根目录 [`AGENTS.md`](../AGENTS.md) 为准；本文保留产品行为规格。

---

## 1. 范围

### 做什么

- 启动后 **仅菜单栏图标**（`LSUIElement`，无 Dock 常驻大窗）
- 托盘菜单启动录制；底部浮层选参数；录制中菜单栏变成控制条；停录后 Files List；可选 Edit

### 尚未做 / 占位

- PiP 摄像头、Click Zoom、键盘捕获、倒计时、帧率/分辨率精细调节
- Convert/Compress、Rename、VIP 等 OMI 扩展
- 应用内 Edit / Export（下一刀优先）

### 身份

| | Value |
|--|-------|
| 产品名 / `.app` | `EggplantRecorder` |
| Bundle ID | `click.yinsb.eggplantrecorder` |
| GitHub | `https://github.com/uniquejava/EggplantRecorder` |
| 最低系统 | **macOS 15+** |
| 开发签名 | 稳定 Apple Development Team（与 Fred 相同 Team，避免每次 rebuild 重授 Screen Recording） |

---

## 2. 用户流程

```text
启动 → 仅菜单栏图标
  ├─ 点击图标 → 弹出菜单
  │    ├─ Record Screen（全屏）
  │    ├─ Record Area（框选 + 底部参数条同时出现）
  │    ├─ Record Window（悬停虚线框 → 点击 → 参数条）
  │    ├─ Show Files List
  │    └─ Quit
  │
  ├─ Screen / Area(框选中) / Window(点选后) → 屏幕底部「参数条」
  │    ├─ Screen：显示器下拉；Window / Area：无源下拉
  │    ├─ System Sound / Microphone（+ 输入设备）/ Capture Mouse Cursor
  │    └─ 红色 Record → 开始录制，参数条（与 Area 遮罩）关闭
  │
  ├─ 录制中 → 菜单栏控制条（Screen / Window）；Area 另见下方虚线框 + mini 面板
  │    ├─ Pause / Resume
  │    ├─ Stop
  │    └─ 已录时长 HH:MM:SS（不含暂停墙钟）
  │
  ├─ Area 录制中 → 所选区域淡蓝虚线框 + 框下方 OMI mini 控制条
  │    ├─ 计时 / Pause / Stop / Restart / Discard（Annotate 占位）
  │    └─ 边框与面板不进成片（excludePID）
  │
  └─ Stop → MP4 写入库目录 → 弹出 Files List
       ├─ Play / Preview / Show in Finder / Delete
       └─ Edit → 轻量裁剪 / Export（待做）
```

---

## 3. UI 规格

### 3.1 空闲托盘图标

- **Template image**（黑 + alpha）；光学约 **16pt** 高
- 左键 / 右键：同一功能菜单
- 空闲时不要显示 “Idle” 长文案

### 3.2 录制中控制

| 控件 | 行为 |
|------|------|
| Pause / Resume | 圆形按钮；暂停时图标切换 |
| Stop | 红方块停止并保存 |
| Timer | `HH:MM:SS`，仅累计「在录」时间 |

- **Screen / Window：** 自定义 `NSStatusItem` 视图（菜单栏控制条）。
- **Area：** 所选区域保留淡蓝虚线框；框下方 OMI 深色 mini 面板（计时 + 圆形按钮：Annotate 占位 / Stop / Pause / Restart / Discard）。菜单栏控制条仍可用作备份。

### 3.3 底部参数条（OMI 深色毛玻璃）

- 屏幕 **底部居中**，距物理底边约 **16pt**，可拖动
- 三栏约 **260 / 260 / 100**，高度约 **230**
- Screen：显示器下拉；Window / Area：无源下拉（点选 / 框选已完成）
- System Sound、Microphone（+ 设备）、Capture Mouse Cursor
- 右侧大红录制圆钮；右上角关闭
- 权限文案：Grant access / Open Settings；列表空 → **Relaunch**

### 3.4 Files List

- 停录先出列表，不要直接进 Editor
- 列：Name、Duration、Size、Type、Date、Operation
- Preview / Play / Edit / Show in Finder / Delete（Convert/Compress、Rename 可占位禁用）

### 3.5 Edit（待做）

- 预览 + 简单 trim + Export MP4

---

## 4. 录制与文件

### 4.1 库目录

- 默认：`~/Movies/EggplantRecorder/`
- 文件名：`Screen-…` / `Window-…` / `Area-…`
- 停录即落盘

### 4.2 Capture 行为

1. macOS only，ScreenCaptureKit
2. 录显示器时排除本 app 窗口（`excludePID`）
3. System audio 与 Microphone 为 **两条独立音轨**
4. Mic：开录前申请 Microphone TCC；Hardened Runtime 需 `device.audio-input`
5. Pause：跳过写 sample，压缩时间线（无冻帧）
6. Area：`sourceRect`；Window：悬停点选 → `window:ID`

### 4.3 权限

`Info.plist` 保留 Screen Recording / Microphone 用途说明。

---

## 5. 验收清单

1. 冷启动：只有菜单栏图标。
2. 菜单：Screen / Area / Window / Files List / Quit。
3. Screen → 参数条 → Record；Area → 框选同时出参数条 → Record；Window → 悬停 → 点击 → 参数条。
4. 录制中：Pause + Stop + 计时；Area 有虚线框 + mini 面板；Pause 后计时停、文件无冻帧。
5. Stop → 库目录出现 MP4 → Files List 打开并高亮。
6. Preview / Finder / Delete / Play 可用；Edit 可二期。
7. 无权限 / 需 Relaunch 时文案正确。
8. 录屏不把本 app 的 Files List / 参数条录进去。

---

## 6. 路线图

| 状态 | 项 |
|------|-----|
| Done | 工程 + SCK 录屏（屏/窗/区）+ 双音轨 + pause |
| Done | OMI 三栏参数条 + Window 悬停点选 + Area 框选 |
| Done | Status Item 控制条 + Files List |
| Next | Edit / Export |
| Later | 占位功能接线；图标打磨 |
