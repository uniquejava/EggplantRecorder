import AppKit
import AVFoundation
import CoreGraphics
import Foundation

enum CapturePermissions {
    static var hasScreenAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Returns true if already granted. Otherwise may open Settings once.
    @discardableResult
    static func requestScreenAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    static func openScreenCaptureSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    static func microphoneAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestMicrophoneAccess() async -> Bool {
        let status = microphoneAuthorizationStatus()
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    static func openMicrophoneSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
