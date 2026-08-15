import AppKit
import AVFoundation
import Foundation
import ScreenCaptureKit

struct CaptureSource: Identifiable, Hashable {
    let id: String
    let kind: RecordingKind
    let name: String
    let width: Int
    let height: Int
}

struct MicrophoneDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let isDefault: Bool
}

enum CaptureSourcesError: LocalizedError {
    case noPermission(String)
    case emptyAfterGrant

    var errorDescription: String? {
        switch self {
        case .noPermission(let message):
            return message
        case .emptyAfterGrant:
            return L10n.tr("sources.emptyAfterGrant")
        }
    }
}

enum CaptureSources {
    static func list(kind: RecordingKind) async throws -> [CaptureSource] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw CaptureSourcesError.noPermission(
                error.localizedDescription.isEmpty
                    ? L10n.tr("sources.grantToList")
                    : error.localizedDescription
            )
        }

        switch kind {
        case .screen:
            let displays = content.displays.map { display in
                CaptureSource(
                    id: "display:\(display.displayID)",
                    kind: .screen,
                    name: L10n.tr("options.screenSize", display.width, display.height),
                    width: display.width,
                    height: display.height
                )
            }
            if displays.isEmpty {
                if CapturePermissions.hasScreenAccess {
                    throw CaptureSourcesError.emptyAfterGrant
                }
                throw CaptureSourcesError.noPermission(
                    "No displays available. Grant Screen Recording access in System Settings."
                )
            }
            return displays
        case .window:
            return content.windows.compactMap { window in
                guard shouldList(window: window) else { return nil }
                let w = Int(max(window.frame.width, 0))
                let h = Int(max(window.frame.height, 0))
                let title = window.title?.isEmpty == false ? window.title! : "Window"
                let app = window.owningApplication?.applicationName ?? "App"
                return CaptureSource(
                    id: "window:\(window.windowID)",
                    kind: .window,
                    name: "\(app) — \(title)",
                    width: w,
                    height: h
                )
            }
        case .area:
            // Area sources come from AreaSelectionController, not SCK enumeration.
            return []
        }
    }

    static func listMicrophones() -> [MicrophoneDevice] {
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID ?? ""
        var devices: [AVCaptureDevice] = []
        let types: [AVCaptureDevice.DeviceType] = [.microphone, .external]
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .audio,
            position: .unspecified
        )
        devices.append(contentsOf: session.devices)

        var unique: [AVCaptureDevice] = []
        var seen = Set<String>()
        for device in devices {
            guard !device.uniqueID.isEmpty, !seen.contains(device.uniqueID) else { continue }
            seen.insert(device.uniqueID)
            unique.append(device)
        }
        if let def = AVCaptureDevice.default(for: .audio),
           !def.uniqueID.isEmpty,
           !seen.contains(def.uniqueID) {
            unique.insert(def, at: 0)
        }

        return unique.map {
            MicrophoneDevice(
                id: $0.uniqueID,
                name: $0.localizedName.isEmpty ? $0.uniqueID : $0.localizedName,
                isDefault: $0.uniqueID == defaultID
            )
        }
    }

    private static func shouldList(window: SCWindow) -> Bool {
        guard let app = window.owningApplication else { return false }
        guard window.isOnScreen, window.windowLayer == 0 else { return false }

        let w = window.frame.width
        let h = window.frame.height
        guard w >= 80, h >= 80 else { return false }

        let selfPID = ProcessInfo.processInfo.processIdentifier
        if app.processID == selfPID { return false }

        let bundleID = app.bundleIdentifier ?? ""
        let appName = app.applicationName
        let bundleLower = bundleID.lowercased()
        let appLower = appName.lowercased()

        let denyExact: Set<String> = [
            "com.apple.dock",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
            "com.apple.screencaptureui",
            "com.apple.Screenshot",
            "com.apple.Spotlight",
            "com.apple.loginwindow",
            "com.apple.WindowManager",
            "com.apple.SystemUIServer",
            "com.apple.TextInputMenuAgent",
            "com.apple.TextInputUI.xpc.CursorUIViewService",
            "com.apple.AccessibilityVisualsAgent",
            "com.apple.PIPAgent",
            "com.apple.UserNotificationCenter",
            "com.apple.chronod",
            "com.apple.wallpaper.agent",
        ]
        if denyExact.contains(bundleID) { return false }

        let denyPrefixes = [
            "com.apple.TextInputUI",
            "com.apple.inputmethod.",
            "com.apple.PressAndHold",
            "com.apple.CoreGlyphs",
            "com.sogou.",
            "com.baidu.inputmethod",
            "com.iflytek.",
            "com.tencent.inputmethod",
            "com.google.inputmethod",
            "com.apple.Hilink",
        ]
        if denyPrefixes.contains(where: { bundleID.hasPrefix($0) }) { return false }

        if bundleLower.contains("inputmethod")
            || bundleLower.contains("textinput")
            || bundleLower.contains(".ime")
            || appLower.contains("input method")
            || appName.contains("输入法")
            || appName.contains("搜狗")
            || appName.contains("百度输入")
            || appName.contains("讯飞") {
            return false
        }

        let title = window.title ?? ""
        if title.isEmpty && (w < 200 || h < 200) {
            return false
        }
        return true
    }
}
