import SwiftUI

struct OptionsBarLeftColumn: View {
    @ObservedObject var model: OptionsBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Window / Area are picked via overlay — no source dropdown.
            if model.mode == .screen {
                sourceRow
            }

            OptionsFeatureRow(
                icon: "waveform",
                title: model.selectedMicName,
                showsMenu: model.microphone && !model.microphones.isEmpty,
                menuItems: model.microphones.map { mic in
                    OptionsMenuItem(
                        id: mic.id,
                        title: mic.isDefault ? L10n.tr("options.micDefault", mic.name) : mic.name,
                        isSelected: mic.id == model.selectedMicID
                    )
                },
                onMenuSelect: { id in
                    model.selectedMicID = id
                    model.microphone = true
                },
                isOn: $model.microphone,
                enabled: true
            )

            OptionsFeatureRow(
                icon: "camera",
                title: L10n.tr("options.pipCamera"),
                showsMenu: true,
                isOn: $model.pipCamera,
                enabled: false
            )

            OptionsFeatureRow(
                icon: "speaker.wave.2",
                title: L10n.tr("options.systemSound"),
                isOn: $model.systemAudio,
                enabled: true
            )

            OptionsFeatureRow(
                icon: "cursorarrow.rays",
                title: L10n.tr("options.captureCursor"),
                isOn: $model.showCursor,
                enabled: true
            )

            OptionsFeatureRow(
                icon: "plus.magnifyingglass",
                title: L10n.tr("options.clickZoom"),
                isOn: $model.clickZoom,
                enabled: false
            )

            OptionsFeatureRow(
                icon: "keyboard",
                title: L10n.tr("options.catchKeyboard"),
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
                title: L10n.tr("common.loading"),
                showsMenu: false,
                isOn: .constant(false),
                enabled: false
            )
        } else {
            OptionsFeatureRow(
                icon: sourceIconName,
                title: model.selectedSourceName,
                showsMenu: !model.sources.isEmpty,
                menuItems: model.sources.map { source in
                    OptionsMenuItem(
                        id: source.id,
                        title: source.name,
                        isSelected: source.id == model.selectedSourceID
                    )
                },
                onMenuSelect: { id in
                    model.selectedSourceID = id
                },
                isOn: .constant(true),
                enabled: !model.sources.isEmpty,
                forceChecked: true
            )
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
        VStack(alignment: .leading, spacing: 10) {
            OptionsParamRow(icon: "rectangle.dashed") {
                Text(L10n.tr("options.size"))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 6)
                OptionsSizeField(text: model.sizeWidthText)
                Text("×")
                    .foregroundStyle(.white.opacity(0.45))
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize()
                OptionsSizeField(text: model.sizeHeightText)
            }

            OptionsParamRow(icon: "film") {
                Text(L10n.tr("options.frameRate"))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 6)
                OptionsPillMenu(
                    text: model.frameRate.label,
                    items: model.frameRateItems,
                    onSelect: { model.selectFrameRate($0) }
                )
            }

            OptionsParamRow(icon: "rectangle.ratio.16.to.9") {
                Text(L10n.tr("options.resolution"))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 6)
                OptionsPillMenu(
                    text: model.resolution.label,
                    items: model.resolutionItems,
                    onSelect: { model.selectResolution($0) }
                )
            }

            OptionsParamRow(icon: "clock") {
                Text(L10n.tr("options.timingRecording"))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 6)
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }

            OptionsParamRow(icon: "timer") {
                Text(L10n.tr("options.countDown"))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 6)
                OptionsPillMenu(
                    text: model.countdown.label,
                    items: model.countdownItems,
                    onSelect: { model.selectCountdown($0) }
                )
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
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
                        .strokeBorder(Color(red: 0.910, green: 0.918, blue: 0.929), lineWidth: 2)
                        .frame(width: 48, height: 48)
                    Circle()
                        .fill(Color(red: 0.882, green: 0.114, blue: 0.094)) // #e11d18
                        .frame(width: 32, height: 32)
                }
                .opacity(canRecord ? 1 : 0.35)
            }
            .buttonStyle(.plain)
            .disabled(!canRecord)
            .help(L10n.tr("options.startRecording"))
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
                Button(L10n.tr("common.grantAccess")) { model.grantAccess() }
                    .controlSize(.small)
                Button(L10n.tr("common.openSettings")) { CapturePermissions.openScreenCaptureSettings() }
                    .controlSize(.small)
            } else if model.permissionState == .needsRelaunch {
                Button(L10n.tr("common.relaunch")) { model.relaunch() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .padding(.top, 2)
    }
}
