import SwiftUI

struct EditorRailView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EditorChrome.muted)
                .tracking(0.6)
                .textCase(.uppercase)

            field(
                "Frame Rate",
                title: model.settings.frameRateTitle(source: model.sourceInfo),
                items: frameRateItems,
                enabled: canEdit
            ) { id in
                if let pick = ExportSettings.FrameRate(rawValue: id) {
                    model.settings.frameRate = pick
                }
            }

            field(
                "Resolution",
                title: model.settings.resolutionTitle(source: model.sourceInfo),
                items: resolutionItems,
                enabled: canEdit
            ) { id in
                if let pick = ExportSettings.Resolution(rawValue: id) {
                    model.settings.resolution = pick
                }
            }

            field(
                "Quality",
                title: model.settings.quality.title,
                items: qualityItems,
                enabled: canEdit
            ) { id in
                if let pick = ExportSettings.Quality(rawValue: id) {
                    model.settings.quality = pick
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Audio")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(EditorChrome.label)
                HStack(spacing: 10) {
                    EditorVolumeSlider(value: $model.settings.volume, enabled: canEdit)
                    Text("\(audioPercent)%")
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(EditorChrome.text)
                        .frame(minWidth: 36, alignment: .trailing)
                }
                Picker("Channels", selection: $model.settings.audioChannels) {
                    Text("Stereo").tag(ExportSettings.AudioChannels.stereo)
                    Text("Mono").tag(ExportSettings.AudioChannels.mono)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!canEdit)
            }

            Spacer(minLength: 8)

            Text(model.estimatedSizeText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(EditorChrome.label)

            Button {
                model.exportPreview()
            } label: {
                Text("Preview 30s")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EditorChrome.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(EditorChrome.secondaryButton)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .opacity(canEdit ? 1 : 0.45)

            Button {
                model.export()
            } label: {
                ZStack {
                    Text(model.isExporting ? "Exporting…" : "Export")
                        .opacity(model.isExporting ? 0 : 1)
                    if model.isExporting {
                        ProgressView(value: model.exportProgress)
                            .progressViewStyle(.linear)
                            .tint(.white)
                            .padding(.horizontal, 10)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(EditorChrome.export)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(model.isExporting || model.duration <= 0 || model.loadFailed)
            .opacity(model.duration > 0 && !model.loadFailed ? 1 : 0.45)
        }
        .padding(16)
        .frame(width: EditorChrome.railWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(EditorChrome.rail)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(EditorChrome.divider)
                .frame(width: 1)
        }
    }

    private var canEdit: Bool {
        !model.isExporting && model.duration > 0 && !model.loadFailed
    }

    private var audioPercent: Int {
        Int((model.settings.volume * 100).rounded())
    }

    private var frameRateItems: [OptionsMenuItem] {
        model.settings.availableFrameRates(source: model.sourceInfo).map { pick in
            var copy = model.settings
            copy.frameRate = pick
            return OptionsMenuItem(
                id: pick.rawValue,
                title: copy.frameRateTitle(source: model.sourceInfo),
                isSelected: model.settings.frameRate == pick
            )
        }
    }

    private var resolutionItems: [OptionsMenuItem] {
        model.settings.availableResolutions(source: model.sourceInfo).map { pick in
            var copy = model.settings
            copy.resolution = pick
            return OptionsMenuItem(
                id: pick.rawValue,
                title: copy.resolutionTitle(source: model.sourceInfo),
                isSelected: model.settings.resolution == pick
            )
        }
    }

    private var qualityItems: [OptionsMenuItem] {
        ExportSettings.Quality.allCases.map {
            OptionsMenuItem(
                id: $0.rawValue,
                title: $0.title,
                isSelected: model.settings.quality == $0
            )
        }
    }

    private func field(
        _ label: String,
        title: String,
        items: [OptionsMenuItem],
        enabled: Bool,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(EditorChrome.label)
            EditorMenuField(title: title, items: items, enabled: enabled, onSelect: onSelect)
        }
    }
}

struct EditorMenuField: View {
    let title: String
    let items: [OptionsMenuItem]
    var enabled: Bool = true
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(enabled ? EditorChrome.text : EditorChrome.muted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(EditorChrome.text.opacity(enabled ? 0.4 : 0.28))
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(enabled ? EditorChrome.field : EditorChrome.secondaryButton)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(enabled ? EditorChrome.fieldStroke : EditorChrome.track, lineWidth: 0.5)
                )
        )
        .overlay {
            if enabled, !items.isEmpty {
                CompactMenuAnchor(items: items, onSelect: onSelect)
            }
        }
        .allowsHitTesting(enabled && !items.isEmpty)
    }
}

struct EditorVolumeSlider: View {
    @Binding var value: Double
    var enabled: Bool = true

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let x = CGFloat(min(max(value, 0), 1)) * width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(EditorChrome.track)
                    .frame(height: 6)
                Capsule()
                    .fill(EditorChrome.export)
                    .frame(width: max(x, 6), height: 6)
                Circle()
                    .fill(EditorChrome.export)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 0.5)
                    .frame(width: 14, height: 14)
                    .offset(x: min(max(x - 7, 0), width - 14))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard enabled else { return }
                        value = min(max(Double(drag.location.x / width), 0), 1)
                    }
            )
        }
        .frame(height: 18)
        .opacity(enabled ? 1 : 0.45)
        .allowsHitTesting(enabled)
    }
}
