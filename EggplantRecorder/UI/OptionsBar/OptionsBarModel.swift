import AppKit
import Combine
import SwiftUI

@MainActor
final class OptionsBarModel: ObservableObject {
    @Published var mode: RecordingKind = .screen
    @Published var sources: [CaptureSource] = []
    @Published var selectedSourceID: String = ""
    @Published var microphones: [MicrophoneDevice] = []
    @Published var selectedMicID: String = ""
    @Published var systemAudio = true
    @Published var microphone = true
    @Published var showCursor = true
    @Published var isLoading = false
    @Published var permissionState: PermissionState = .unknown
    @Published var bannerMessage: String?

    // Placeholders (UI only — not wired into capture yet).
    @Published var pipCamera = false
    @Published var clickZoom = false
    @Published var catchKeyboard = false
    @Published var frameRateLabel = "30FPS"
    @Published var resolutionLabel = "Native"
    @Published var countdownLabel = "none"

    enum PermissionState {
        case unknown
        case granted
        case needsGrant
        case needsRelaunch
    }

    var onClose: (() -> Void)?
    var onRecord: ((RecordingConfig) -> Void)?
    /// Called when content height may change (permission banner, source reload).
    var onContentSizeMayChange: (() -> Void)?

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    var sizeWidthText: String {
        if mode == .window, let hit = appState?.pendingWindow?.hit {
            let scale = screenScale(for: hit.frame)
            return "\(max(2, Int(hit.frame.width * scale) / 2 * 2))"
        }
        if let source = sources.first(where: { $0.id == selectedSourceID }) {
            return "\(source.width)"
        }
        if mode == .area, let area = appState?.pendingArea {
            return "\(area.pixelWidth)"
        }
        return "—"
    }

    var sizeHeightText: String {
        if mode == .window, let hit = appState?.pendingWindow?.hit {
            let scale = screenScale(for: hit.frame)
            return "\(max(2, Int(hit.frame.height * scale) / 2 * 2))"
        }
        if let source = sources.first(where: { $0.id == selectedSourceID }) {
            return "\(source.height)"
        }
        if mode == .area, let area = appState?.pendingArea {
            return "\(area.pixelHeight)"
        }
        return "—"
    }

    private func screenScale(for rect: CGRect) -> CGFloat {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main
        return screen?.backingScaleFactor ?? 2
    }

    var selectedMicName: String {
        guard let mic = microphones.first(where: { $0.id == selectedMicID }) else {
            return "Microphone"
        }
        return mic.isDefault ? "\(mic.name) (Default)" : mic.name
    }

    var selectedSourceName: String {
        sources.first(where: { $0.id == selectedSourceID })?.name
            ?? (mode == .area ? "No area" : "No source")
    }

    func prepare(mode: RecordingKind) {
        self.mode = mode
        bannerMessage = nil
        Task { await reload() }
    }

    /// Called while the area overlay is live so Size / Record enablement stay in sync.
    func noteAreaSelectionChanged() {
        guard mode == .area else { return }
        if let area = appState?.pendingArea {
            let source = CaptureSource(
                id: "display:\(area.displayID)",
                kind: .area,
                name: "Area \(area.pixelWidth)×\(area.pixelHeight)",
                width: area.pixelWidth,
                height: area.pixelHeight
            )
            sources = [source]
            selectedSourceID = source.id
            if permissionState != .needsGrant && permissionState != .needsRelaunch {
                permissionState = CapturePermissions.hasScreenAccess ? .granted : .needsGrant
            }
            bannerMessage = nil
        } else {
            sources = []
            selectedSourceID = ""
            bannerMessage = "Drag to select an area."
        }
        onContentSizeMayChange?()
    }

    func reload() async {
        isLoading = true
        defer {
            isLoading = false
            onContentSizeMayChange?()
        }

        microphones = CaptureSources.listMicrophones()
        if selectedMicID.isEmpty {
            selectedMicID = microphones.first(where: \.isDefault)?.id ?? microphones.first?.id ?? ""
        }

        if mode == .area {
            await reloadArea()
            return
        }

        if mode == .window {
            await reloadWindow()
            return
        }

        if !CapturePermissions.hasScreenAccess {
            permissionState = .needsGrant
            sources = []
            selectedSourceID = ""
            return
        }

        do {
            let list = try await CaptureSources.list(kind: mode)
            sources = list
            if list.isEmpty {
                permissionState = .needsRelaunch
                selectedSourceID = ""
            } else {
                permissionState = .granted
                if !list.contains(where: { $0.id == selectedSourceID }) {
                    selectedSourceID = list.first?.id ?? ""
                }
            }
        } catch CaptureSourcesError.emptyAfterGrant {
            permissionState = .needsRelaunch
            sources = []
            selectedSourceID = ""
        } catch {
            if CapturePermissions.hasScreenAccess {
                permissionState = .needsRelaunch
            } else {
                permissionState = .needsGrant
            }
            bannerMessage = error.localizedDescription
            sources = []
            selectedSourceID = ""
        }
    }

    private func reloadArea() async {
        guard let area = appState?.pendingArea else {
            permissionState = .needsGrant
            sources = []
            selectedSourceID = ""
            bannerMessage = "No area selected. Pick Record Area again."
            return
        }

        let source = CaptureSource(
            id: "display:\(area.displayID)",
            kind: .area,
            name: "Area \(area.pixelWidth)×\(area.pixelHeight)",
            width: area.pixelWidth,
            height: area.pixelHeight
        )
        sources = [source]
        selectedSourceID = source.id
        await probeScreenPermission(listing: .screen)
    }

    private func reloadWindow() async {
        guard let pending = appState?.pendingWindow else {
            permissionState = .needsGrant
            sources = []
            selectedSourceID = ""
            bannerMessage = "No window selected. Pick Record Window again."
            return
        }

        let hit = pending.hit
        let pixelScale: CGFloat = {
            let screen = NSScreen.screens.first(where: { $0.frame.intersects(hit.frame) }) ?? NSScreen.main
            return screen?.backingScaleFactor ?? 2
        }()
        let width = max(2, Int(hit.frame.width * pixelScale) / 2 * 2)
        let height = max(2, Int(hit.frame.height * pixelScale) / 2 * 2)

        let source = CaptureSource(
            id: hit.sourceID,
            kind: .window,
            name: hit.displayName,
            width: width,
            height: height
        )
        sources = [source]
        selectedSourceID = source.id
        await probeScreenPermission(listing: .window)
    }

    /// Touch SCK so “granted but empty” relaunch still surfaces (Area / Window pick).
    private func probeScreenPermission(listing kind: RecordingKind) async {
        if !CapturePermissions.hasScreenAccess {
            permissionState = .needsGrant
            return
        }
        do {
            _ = try await CaptureSources.list(kind: kind)
            permissionState = .granted
        } catch CaptureSourcesError.emptyAfterGrant {
            permissionState = .needsRelaunch
        } catch {
            permissionState = CapturePermissions.hasScreenAccess ? .needsRelaunch : .needsGrant
            bannerMessage = error.localizedDescription
        }
    }

    func grantAccess() {
        _ = CapturePermissions.requestScreenAccess()
        CapturePermissions.openScreenCaptureSettings()
        Task { await reload() }
    }

    func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func startRecording() {
        guard let source = sources.first(where: { $0.id == selectedSourceID }) else {
            bannerMessage = permissionState == .needsGrant
                ? "Grant Screen Recording access first."
                : "Pick a capture source."
            return
        }
        if microphone {
            Task {
                let ok = await CapturePermissions.requestMicrophoneAccess()
                if !ok {
                    bannerMessage = "Microphone permission is required. Enable it in System Settings."
                    CapturePermissions.openMicrophoneSettings()
                    return
                }
                fireRecord(source: source)
            }
        } else {
            fireRecord(source: source)
        }
    }

    private func fireRecord(source: CaptureSource) {
        let area = appState?.pendingArea
        let config = RecordingConfig(
            kind: mode,
            sourceID: source.id,
            systemAudio: systemAudio,
            microphone: microphone,
            microphoneDeviceID: microphone ? selectedMicID : nil,
            showCursor: showCursor,
            areaSourceRect: mode == .area ? area?.sourceRect : nil,
            areaPixelWidth: mode == .area ? area?.pixelWidth : nil,
            areaPixelHeight: mode == .area ? area?.pixelHeight : nil
        )
        onRecord?(config)
    }
}
