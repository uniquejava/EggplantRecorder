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

        if !CapturePermissions.hasScreenAccess {
            permissionState = .needsGrant
            return
        }
        do {
            _ = try await CaptureSources.list(kind: .screen)
            permissionState = .granted
        } catch CaptureSourcesError.emptyAfterGrant {
            permissionState = .needsRelaunch
        } catch {
            if CapturePermissions.hasScreenAccess {
                permissionState = .needsRelaunch
            } else {
                permissionState = .needsGrant
            }
            bannerMessage = error.localizedDescription
        }
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

        if !CapturePermissions.hasScreenAccess {
            permissionState = .needsGrant
            return
        }
        do {
            // Touch SCK so “granted but empty” relaunch still surfaces.
            _ = try await CaptureSources.list(kind: .window)
            permissionState = .granted
        } catch CaptureSourcesError.emptyAfterGrant {
            permissionState = .needsRelaunch
        } catch {
            if CapturePermissions.hasScreenAccess {
                permissionState = .needsRelaunch
            } else {
                permissionState = .needsGrant
            }
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

// MARK: - Root view

struct OptionsBarView: View {
    @ObservedObject var model: OptionsBarModel

    /// OMI-like column widths: 260 + 260 + 100 (+ 2 dividers).
    private let leftWidth: CGFloat = 260
    private let middleWidth: CGFloat = 260
    private let rightWidth: CGFloat = 100
    private let panelHeight: CGFloat = 230
    private let cornerRadius: CGFloat = 20

    private var panelWidth: CGFloat { leftWidth + middleWidth + rightWidth + 2 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                leftColumn
                    .padding(.horizontal, 16)
                    .frame(width: leftWidth, alignment: .leading)

                columnDivider

                middleColumn
                    .padding(.horizontal, 16)
                    .frame(width: middleWidth, alignment: .leading)

                columnDivider

                rightColumn
                    .frame(width: rightWidth)
            }
            .frame(width: panelWidth, height: panelHeight)

            if let banner = permissionBanner ?? model.bannerMessage {
                permissionFooter(banner)
            }
        }
        .frame(width: panelWidth)
        .overlay(alignment: .topTrailing) {
            Button {
                model.onClose?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 8)
            .help("Close")
        }
        .background {
            ZStack {
                VisualEffectBackground(material: .hudWindow)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        // No outer padding — that left a gray halo around the glass inside the NSPanel.
        .gesture(WindowDragGesture())
        .preferredColorScheme(.dark)
    }

    // MARK: Columns

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Window is picked via hover overlay — no source dropdown (OMI-like).
            if model.mode != .window {
                sourceRow
            }

            featureRow(
                icon: "waveform",
                title: model.selectedMicName,
                showsMenu: model.microphone && !model.microphones.isEmpty,
                isOn: $model.microphone,
                enabled: true
            ) {
                ForEach(model.microphones) { mic in
                    Button {
                        model.selectedMicID = mic.id
                        model.microphone = true
                    } label: {
                        if mic.id == model.selectedMicID {
                            Label(mic.isDefault ? "\(mic.name) (Default)" : mic.name, systemImage: "checkmark")
                        } else {
                            Text(mic.isDefault ? "\(mic.name) (Default)" : mic.name)
                        }
                    }
                }
            }

            featureRow(
                icon: "camera",
                title: "PiP Camera",
                showsMenu: true,
                isOn: $model.pipCamera,
                enabled: false
            )

            featureRow(
                icon: "speaker.wave.2",
                title: "System Sound",
                isOn: $model.systemAudio,
                enabled: true
            )

            featureRow(
                icon: "cursorarrow.rays",
                title: "Capture Mouse Cursor",
                isOn: $model.showCursor,
                enabled: true
            )

            featureRow(
                icon: "plus.magnifyingglass",
                title: "Click Zoom",
                isOn: $model.clickZoom,
                enabled: false
            )

            featureRow(
                icon: "keyboard",
                title: "Catch Keyboard Event",
                showsGear: true,
                isOn: $model.catchKeyboard,
                enabled: false
            )
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var middleColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            paramRow(icon: "rectangle.dashed") {
                Text("Size")
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 6)
                sizeField(model.sizeWidthText)
                Text("×")
                    .foregroundStyle(.white.opacity(0.45))
                    .font(.system(size: 12, weight: .medium))
                sizeField(model.sizeHeightText)
            }

            paramRow(icon: "film") {
                Text("Frame Rate")
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 6)
                pillLabel(model.frameRateLabel, enabled: false)
            }

            paramRow(icon: "rectangle.ratio.16.to.9") {
                Text("Resolution")
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 6)
                pillLabel(model.resolutionLabel, enabled: false)
            }

            paramRow(icon: "clock") {
                Text("Timing Recording")
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 6)
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }

            paramRow(icon: "timer") {
                Text("Count Down")
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 6)
                pillLabel(model.countdownLabel, enabled: false)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .opacity(0.95)
    }

    private var rightColumn: some View {
        VStack {
            Spacer(minLength: 0)
            Button {
                model.startRecording()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.92), lineWidth: 3)
                        .frame(width: 64, height: 64)
                    Circle()
                        .fill(Color(red: 1, green: 0.23, blue: 0.19))
                        .frame(width: 48, height: 48)
                        .shadow(color: Color.red.opacity(0.45), radius: 8, y: 2)
                }
                .opacity(canRecord ? 1 : 0.35)
            }
            .buttonStyle(.plain)
            .disabled(!canRecord)
            .help("Start recording")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var columnDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1)
            .padding(.vertical, 4)
    }

    // MARK: Rows

    @ViewBuilder
    private var sourceRow: some View {
        let icon = sourceIconName
        if model.mode == .area {
            featureRowLabel(
                icon: icon,
                title: model.selectedSourceName,
                showsMenu: false,
                showsGear: false,
                isOn: .constant(true),
                enabled: false,
                forceChecked: true
            )
        } else if model.isLoading {
            featureRowLabel(
                icon: icon,
                title: "Loading…",
                showsMenu: false,
                showsGear: false,
                isOn: .constant(false),
                enabled: false
            )
        } else {
            featureRow(
                icon: icon,
                title: model.selectedSourceName,
                showsMenu: !model.sources.isEmpty,
                isOn: .constant(true),
                enabled: !model.sources.isEmpty,
                forceChecked: true
            ) {
                ForEach(model.sources) { source in
                    Button {
                        model.selectedSourceID = source.id
                    } label: {
                        if source.id == model.selectedSourceID {
                            Label(source.name, systemImage: "checkmark")
                        } else {
                            Text(source.name)
                        }
                    }
                }
            }
        }
    }

    private var sourceIconName: String {
        switch model.mode {
        case .screen: return "display"
        case .window: return "macwindow"
        case .area: return "rectangle.dashed"
        }
    }

    private func featureRow(
        icon: String,
        title: String,
        showsMenu: Bool = false,
        showsGear: Bool = false,
        isOn: Binding<Bool>,
        enabled: Bool,
        forceChecked: Bool = false,
        @ViewBuilder menuContent: () -> some View = { EmptyView() }
    ) -> some View {
        featureRowLabel(
            icon: icon,
            title: title,
            showsMenu: showsMenu,
            showsGear: showsGear,
            isOn: isOn,
            enabled: enabled,
            forceChecked: forceChecked,
            menuContent: menuContent
        )
    }

    private func featureRowLabel(
        icon: String,
        title: String,
        showsMenu: Bool,
        showsGear: Bool,
        isOn: Binding<Bool>,
        enabled: Bool,
        forceChecked: Bool = false,
        @ViewBuilder menuContent: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.35))
                .frame(width: 18)

            if showsMenu, enabled {
                Menu {
                    menuContent()
                } label: {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .menuStyle(.borderlessButton)
            } else {
                Text(title)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.white.opacity(enabled ? 0.92 : 0.4))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if showsMenu {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.22))
                }
            }

            if showsGear {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(enabled ? 0.55 : 0.28))
            }

            Spacer(minLength: 6)

            OMICheckbox(
                isOn: isOn,
                enabled: enabled && !forceChecked,
                forceOn: forceChecked
            )
        }
        .frame(minHeight: 22)
        .opacity(enabled || forceChecked ? 1 : 0.72)
    }

    private func paramRow<Content: View>(
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 18)
            content()
                .font(.system(size: 13))
        }
        .frame(minHeight: 24)
    }

    private func sizeField(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
            .frame(minWidth: 44)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
    }

    private func pillLabel(_ text: String, enabled: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(enabled ? Color.black.opacity(0.85) : Color.black.opacity(0.45))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(enabled ? 0.95 : 0.55))
            )
    }

    private func permissionFooter(_ banner: String) -> some View {
        HStack(spacing: 10) {
            Text(banner)
                .font(.system(size: 11))
                .foregroundStyle(Color.orange.opacity(0.95))
                .lineLimit(2)
            Spacer(minLength: 8)
            if model.permissionState == .needsGrant {
                Button("Grant access") { model.grantAccess() }
                    .controlSize(.small)
                Button("Open Settings") { CapturePermissions.openScreenCaptureSettings() }
                    .controlSize(.small)
            } else if model.permissionState == .needsRelaunch {
                Button("Relaunch") { model.relaunch() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 4)
    }

    private var canRecord: Bool {
        model.permissionState == .granted && !model.selectedSourceID.isEmpty
    }

    private var permissionBanner: String? {
        switch model.permissionState {
        case .needsGrant:
            return "Screen Recording access is required. Grant access, then relaunch if sources stay empty."
        case .needsRelaunch:
            return "Permission looks enabled but no sources appeared. Relaunch EggplantRecorder (closing the panel is not enough)."
        default:
            return nil
        }
    }
}

// MARK: - Checkbox

private struct OMICheckbox: View {
    @Binding var isOn: Bool
    var enabled: Bool = true
    var forceOn: Bool = false

    private var checked: Bool { forceOn || isOn }

    var body: some View {
        Button {
            guard enabled else { return }
            isOn.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(checked ? Color(red: 0.04, green: 0.52, blue: 1) : Color.white.opacity(0.001))
                .frame(width: 15, height: 15)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(checked ? Color.clear : Color.white.opacity(enabled ? 0.45 : 0.22), lineWidth: 1.2)
                )
                .overlay {
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                // Unchecked was Color.clear → SwiftUI skipped hit-testing, so only uncheck worked.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || forceOn ? 1 : 0.55)
    }
}

// MARK: - Glass backdrop

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}
