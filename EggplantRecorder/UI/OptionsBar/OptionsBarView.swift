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
    @Published var isLoading = false
    @Published var permissionState: PermissionState = .unknown
    @Published var bannerMessage: String?

    enum PermissionState {
        case unknown
        case granted
        case needsGrant
        case needsRelaunch
    }

    var onClose: (() -> Void)?
    var onRecord: ((RecordingConfig) -> Void)?

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func prepare(mode: RecordingKind) {
        self.mode = mode
        bannerMessage = nil
        Task { await reload() }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        microphones = CaptureSources.listMicrophones()
        if selectedMicID.isEmpty {
            selectedMicID = microphones.first(where: \.isDefault)?.id ?? microphones.first?.id ?? ""
        }

        if mode == .area {
            await reloadArea()
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
        // Touch SCK once so “granted but empty” relaunch case still surfaces.
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
            areaSourceRect: mode == .area ? area?.sourceRect : nil,
            areaPixelWidth: mode == .area ? area?.pixelWidth : nil,
            areaPixelHeight: mode == .area ? area?.pixelHeight : nil
        )
        onRecord?(config)
    }
}

struct OptionsBarView: View {
    @ObservedObject var model: OptionsBarModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                sourcePicker
                Divider().frame(height: 28)
                Toggle("System Sound", isOn: $model.systemAudio)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                HStack(spacing: 8) {
                    Toggle("Microphone", isOn: $model.microphone)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    if model.microphone {
                        Picker("", selection: $model.selectedMicID) {
                            ForEach(model.microphones) { mic in
                                Text(mic.isDefault ? "\(mic.name) (Default)" : mic.name)
                                    .tag(mic.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    model.startRecording()
                } label: {
                    Text("Record")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.red))
                }
                .buttonStyle(.plain)
                .disabled(model.permissionState != .granted || model.selectedSourceID.isEmpty)

                Button {
                    model.onClose?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if let banner = permissionBanner ?? model.bannerMessage {
                HStack(spacing: 10) {
                    Text(banner)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                    Spacer()
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
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 720)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.13).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        )
        .foregroundStyle(.white)
        .padding(8)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sourcePickerTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if model.mode == .area {
                Text(model.sources.first?.name ?? "No area")
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 180, maxWidth: 240, alignment: .leading)
            } else {
                Picker("", selection: $model.selectedSourceID) {
                    ForEach(model.sources) { source in
                        Text(source.name).tag(source.id)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 180, maxWidth: 240)
                .disabled(model.sources.isEmpty)
            }
        }
    }

    private var sourcePickerTitle: String {
        switch model.mode {
        case .screen: return "Display"
        case .window: return "Window"
        case .area: return "Selection"
        }
    }

    private var permissionBanner: String? {
        switch model.permissionState {
        case .needsGrant:
            return "Screen Recording access is required. Grant access, then relaunch if the source list stays empty."
        case .needsRelaunch:
            return "Permission looks enabled but no sources appeared. Relaunch EggplantRecorder (closing the panel is not enough)."
        default:
            return nil
        }
    }
}
