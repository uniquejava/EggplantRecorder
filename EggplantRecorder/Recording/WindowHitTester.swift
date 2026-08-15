import AppKit
import CoreGraphics
import Foundation

struct WindowHit: Equatable {
    let windowID: CGWindowID
    /// Cocoa global coordinates (points, bottom-left origin).
    let frame: CGRect
    let title: String
    let ownerName: String

    var displayName: String {
        if !title.isEmpty {
            return "\(ownerName) — \(title)"
        }
        return ownerName.isEmpty ? "Window" : ownerName
    }

    var sourceID: String { "window:\(windowID)" }
}

/// Front-to-back hit testing of on-screen app windows (ported from EggplantShot).
/// Recording needs `windowID` for ScreenCaptureKit, not just the frame.
struct WindowHitTester {
    private let hits: [WindowHit]

    static func snapshot(excludingPID pid: pid_t = ProcessInfo.processInfo.processIdentifier) -> WindowHitTester {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return WindowHitTester(hits: [])
        }

        let dockLevel = CGWindowLevelForKey(.dockWindow)
        var hits: [WindowHit] = []
        hits.reserveCapacity(infoList.count)

        for info in infoList {
            if let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid {
                continue
            }
            let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
            guard layer < Int(dockLevel) else { continue }

            guard let number = info[kCGWindowNumber as String] as? NSNumber else { continue }
            let windowID = CGWindowID(truncating: number)

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let quartz = cgRect(fromWindowBounds: boundsDict)
            else { continue }
            guard quartz.width >= 40, quartz.height >= 40 else { continue }

            let owner = (info[kCGWindowOwnerName as String] as? String) ?? ""
            let title = (info[kCGWindowName as String] as? String) ?? ""
            // Skip nameless system chrome that still passes the layer filter.
            if owner.isEmpty && title.isEmpty { continue }

            hits.append(
                WindowHit(
                    windowID: windowID,
                    frame: quartzRectToCocoa(quartz),
                    title: title,
                    ownerName: owner
                )
            )
        }

        return WindowHitTester(hits: hits)
    }

    func hit(at point: CGPoint) -> WindowHit? {
        hits.first { $0.frame.contains(point) }
    }

    /// Current frame of one window in Cocoa global points, or nil when it is gone / off-screen
    /// (closed, minimized, another Space). Used to keep recording chrome glued to the window.
    /// `kCGWindowIsOnscreen` is *absent* — not `false` — for off-screen windows, so require it.
    static func liveFrame(of windowID: CGWindowID) -> CGRect? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let info = infoList.first,
              (info[kCGWindowIsOnscreen as String] as? Bool) == true,
              let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
              let quartz = cgRect(fromWindowBounds: boundsDict),
              quartz.width > 1, quartz.height > 1
        else { return nil }
        return quartzRectToCocoa(quartz)
    }

    private static func cgRect(fromWindowBounds dict: [String: Any]) -> CGRect? {
        func num(_ key: String) -> CGFloat? {
            if let n = dict[key] as? CGFloat { return n }
            if let n = dict[key] as? NSNumber { return CGFloat(truncating: n) }
            return nil
        }
        guard let x = num("X"), let y = num("Y"), let w = num("Width"), let h = num("Height") else {
            return nil
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Quartz global (top-left of main display) → Cocoa global (bottom-left of main display).
    private static func quartzRectToCocoa(_ quartz: CGRect) -> CGRect {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let mainHeight = primary?.frame.height ?? CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(
            x: quartz.origin.x,
            y: mainHeight - quartz.origin.y - quartz.height,
            width: quartz.width,
            height: quartz.height
        )
    }
}
