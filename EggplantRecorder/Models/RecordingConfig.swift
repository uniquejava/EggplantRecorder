import CoreGraphics
import Foundation

struct RecordingConfig {
    var kind: RecordingKind
    var sourceID: String
    var systemAudio: Bool
    var microphone: Bool
    var microphoneDeviceID: String?
    var showCursor: Bool = true
    var areaSourceRect: CGRect?
    var areaPixelWidth: Int?
    var areaPixelHeight: Int?
}
