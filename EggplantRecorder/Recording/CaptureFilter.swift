import CoreGraphics
import Foundation
import ScreenCaptureKit

struct CaptureFilterAndSize {
    let filter: SCContentFilter
    let width: Int
    let height: Int
    let sourceRect: CGRect?
}

enum CaptureFilter {
    static func make(
        content: SCShareableContent,
        sourceID: String,
        kind: RecordingKind,
        excludePID: pid_t,
        areaSourceRect: CGRect?,
        areaPixelWidth: Int?,
        areaPixelHeight: Int?
    ) throws -> CaptureFilterAndSize {
        switch kind {
        case .screen, .area:
            var displayID: UInt32 = 0
            if sourceID.hasPrefix("display:") {
                displayID = UInt32(String(sourceID.dropFirst("display:".count))) ?? 0
            }
            let matched = content.displays.first { $0.displayID == displayID } ?? content.displays.first
            guard let matched else {
                throw CaptureError.displayNotFound
            }

            var excluded: [SCWindow] = []
            if excludePID > 0 {
                excluded = content.windows.filter { $0.owningApplication?.processID == excludePID }
            }
            let filter = SCContentFilter(display: matched, excludingWindows: excluded)

            if kind == .area, let areaSourceRect, let areaPixelWidth, let areaPixelHeight {
                var width = areaPixelWidth
                var height = areaPixelHeight
                width -= width % 2
                height -= height % 2
                if width < 2 { width = 2 }
                if height < 2 { height = 2 }
                return CaptureFilterAndSize(
                    filter: filter,
                    width: width,
                    height: height,
                    sourceRect: areaSourceRect
                )
            }

            var width = matched.width
            var height = matched.height
            width -= width % 2
            height -= height % 2
            return CaptureFilterAndSize(filter: filter, width: width, height: height, sourceRect: nil)

        case .window:
            var windowID: UInt32 = 0
            if sourceID.hasPrefix("window:") {
                windowID = UInt32(String(sourceID.dropFirst("window:".count))) ?? 0
            }
            guard let matched = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureError.windowNotFound
            }
            var width = Int(matched.frame.width)
            var height = Int(matched.frame.height)
            width -= width % 2
            height -= height % 2
            if width < 2 { width = 2 }
            if height < 2 { height = 2 }
            let filter = SCContentFilter(desktopIndependentWindow: matched)
            return CaptureFilterAndSize(filter: filter, width: width, height: height, sourceRect: nil)
        }
    }
}
