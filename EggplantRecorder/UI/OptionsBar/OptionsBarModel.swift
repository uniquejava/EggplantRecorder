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
    /// Record was tapped and a start is in flight (mic prompt / stream setup). Keeps the
    /// button inert so a second tap can't fire a second `onRecord` (audit #1).
    @Published var isBusy = false
    @Published var permissionState: PermissionState = .unknown
    @Published var bannerMessage: String?

    // Placeholders (need camera / click / key compositing — not capture-config).
    @Published var pipCamera = false
    @Published var clickZoom = false
    @Published var catchKeyboard = false

    @Published var frameRate: CaptureFrameRate {
        didSet { persist() }
    }
    @Published var resolution: CaptureResolution {
        didSet { persist() }
    }
    @Published var countdown: CaptureCountdown {
        didSet { persist() }
    }

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
        let prefs = AppPreferences.shared
        self.frameRate = prefs.defaultFrameRate
        self.resolution = prefs.defaultResolution
        self.countdown = prefs.defaultCountdown
    }

    var frameRateItems: [OptionsMenuItem] {
        CaptureFrameRate.allCases.map {
            OptionsMenuItem(id: String($0.rawValue), title: $0.label, isSelected: $0 == frameRate)
        }
    }

    var resolutionItems: [OptionsMenuItem] {
        availableResolutions.map {
            OptionsMenuItem(id: $0.rawValue, title: $0.label, isSelected: $0 == resolution)
        }
    }

    var countdownItems: [OptionsMenuItem] {
        CaptureCountdown.allCases.map {
            OptionsMenuItem(id: String($0.rawValue), title: $0.label, isSelected: $0 == countdown)
        }
    }

    var availableResolutions: [CaptureResolution] {
        CaptureResolution.available(sourceHeight: nativePixelSize.height)
    }

    var sizeWidthText: String {
        let size = nativePixelSize
        guard size.width > 0 else { return "—" }
        return "\(resolution.outputSize(width: size.width, height: size.height).0)"
    }

    var sizeHeightText: String {
        let size = nativePixelSize
        guard size.height > 0 else { return "—" }
        return "\(resolution.outputSize(width: size.width, height: size.height).1)"
    }

    private var nativePixelSize: (width: Int, height: Int) {
        if mode == .window, let hit = appState?.pendingWindow?.hit {
            let scale = screenScale(for: hit.frame)
            return (
                max(2, Int(hit.frame.width * scale) / 2 * 2),
                max(2, Int(hit.frame.height * scale) / 2 * 2)
            )
        }
        if let source = sources.first(where: { $0.id == selectedSourceID }) {
            return (source.width, source.height)
        }
        if mode == .area, let area = appState?.pendingArea {
            return (area.pixelWidth, area.pixelHeight)
        }
        return (0, 0)
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
        isBusy = false
        syncCaptureDefaultsFromPreferences()
        Task { await reload() }
    }

    private func syncCaptureDefaultsFromPreferences() {
        let prefs = AppPreferences.shared
        frameRate = prefs.defaultFrameRate
        resolution = prefs.defaultResolution
        countdown = prefs.defaultCountdown
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
            clampResolutionIfNeeded()
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
                clampResolutionIfNeeded()
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
        clampResolutionIfNeeded()
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
        clampResolutionIfNeeded()
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
        guard !isBusy else { return }
        guard let source = sources.first(where: { $0.id == selectedSourceID }) else {
            bannerMessage = permissionState == .needsGrant
                ? "Grant Screen Recording access first."
                : "Pick a capture source."
            return
        }
        isBusy = true
        if microphone {
            Task {
                let ok = await CapturePermissions.requestMicrophoneAccess()
                if !ok {
                    isBusy = false
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
        clampResolutionIfNeeded()
        let config = RecordingConfig(
            kind: mode,
            sourceID: source.id,
            systemAudio: systemAudio,
            microphone: microphone,
            microphoneDeviceID: microphone ? selectedMicID : nil,
            showCursor: showCursor,
            frameRate: frameRate,
            resolution: resolution,
            countdown: countdown,
            areaSourceRect: mode == .area ? area?.sourceRect : nil,
            areaPixelWidth: mode == .area ? area?.pixelWidth : nil,
            areaPixelHeight: mode == .area ? area?.pixelHeight : nil
        )
        onRecord?(config)
    }

    func selectFrameRate(_ id: String) {
        guard let value = Int(id), let pick = CaptureFrameRate(rawValue: value) else { return }
        frameRate = pick
    }

    func selectResolution(_ id: String) {
        guard let pick = CaptureResolution(rawValue: id) else { return }
        resolution = pick
        clampResolutionIfNeeded()
    }

    func selectCountdown(_ id: String) {
        guard let value = Int(id), let pick = CaptureCountdown(rawValue: value) else { return }
        countdown = pick
    }

    private func clampResolutionIfNeeded() {
        if !availableResolutions.contains(resolution) {
            resolution = .native
        }
    }

    private func persist() {
        let prefs = AppPreferences.shared
        prefs.defaultFrameRate = frameRate
        prefs.defaultResolution = resolution
        prefs.defaultCountdown = countdown
    }
}
