import SwiftUI

struct OptionsBarLeftColumn: View {
    @ObservedObject var model: OptionsBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Window / Area are picked via overlay — no source dropdown (OMI-like).
            if model.mode == .screen {
                sourceRow
            }

            OptionsFeatureRow(
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

            OptionsFeatureRow(
                icon: "camera",
                title: "PiP Camera",
                showsMenu: true,
                isOn: $model.pipCamera,
                enabled: false
            )

            OptionsFeatureRow(
                icon: "speaker.wave.2",
                title: "System Sound",
                isOn: $model.systemAudio,
                enabled: true
            )

            OptionsFeatureRow(
                icon: "cursorarrow.rays",
                title: "Capture Mouse Cursor",
                isOn: $model.showCursor,
                enabled: true
            )

            OptionsFeatureRow(
                icon: "plus.magnifyingglass",
                title: "Click Zoom",
                isOn: $model.clickZoom,
                enabled: false
            )

            OptionsFeatureRow(
                icon: "keyboard",
                title: "Catch Keyboard Event",
                showsGear: true,
                isOn: $model.catchKeyboard,
                enabled: false
            )
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var sourceRow: some View {
        if model.isLoading {
            OptionsFeatureRow(
                icon: sourceIconName,
                title: "Loading…",
                showsMenu: false,
                isOn: .constant(false),
                enabled: false
            )
        } else {
            OptionsFeatureRow(
                icon: sourceIconName,
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
}

struct OptionsBarMiddleColumn: View {
    @ObservedObject var model: OptionsBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OptionsParamRow(icon: "rectangle.dashed") {
                Text("Size")
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 6)
                OptionsSizeField(text: model.sizeWidthText)
                Text("×")
                    .foregroundStyle(.white.opacity(0.45))
                    .font(.system(size: 12, weight: .medium))
                OptionsSizeField(text: model.sizeHeightText)
            }

            OptionsParamRow(icon: "film") {
                Text("Frame Rate")
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 6)
                OptionsPillLabel(text: model.frameRateLabel, enabled: false)
            }

            OptionsParamRow(icon: "rectangle.ratio.16.to.9") {
                Text("Resolution")
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 6)
                OptionsPillLabel(text: model.resolutionLabel, enabled: false)
            }

            OptionsParamRow(icon: "clock") {
                Text("Timing Recording")
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 6)
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }

            OptionsParamRow(icon: "timer") {
                Text("Count Down")
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 6)
                OptionsPillLabel(text: model.countdownLabel, enabled: false)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .opacity(0.95)
    }
}

struct OptionsBarRightColumn: View {
    @ObservedObject var model: OptionsBarModel
    let canRecord: Bool

    var body: some View {
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
}

struct OptionsBarPermissionFooter: View {
    @ObservedObject var model: OptionsBarModel
    let banner: String

    var body: some View {
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
}
