import AppKit
import SwiftUI

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                preview
                controls
            }
            EditorRailView(model: model)
        }
        .background(EditorChrome.window)
        .preferredColorScheme(.light)
        .frame(minWidth: 1000, minHeight: 640)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onChange(of: model.settings.volume) { _, volume in
            model.player.volume = Float(volume)
        }
        .onKeyPress(.space, phases: .down) { _ in
            model.togglePlay()
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
            let step: TimeInterval = press.modifiers.contains(.option) ? 0.1 : 1
            model.skip(press.key == .leftArrow ? -step : step)
            return .handled
        }
        .alert(L10n.tr("export.couldNotExport"), isPresented: alertPresented) {
            Button(L10n.tr("common.ok"), role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }

    private var preview: some View {
        ZStack {
            Color.black
            if model.loadFailed {
                ContentUnavailableView(
                    L10n.tr("files.couldNotOpen"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(model.name)
                )
                .foregroundStyle(.white)
            } else if let previewPlayer = model.previewPlayer {
                PlayerPreviewView(player: previewPlayer)
                VStack {
                    HStack {
                        Spacer()
                        Button(L10n.tr("editor.closePreview")) {
                            model.closePreview()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(12)
                    }
                    Spacer()
                }
            } else {
                PlayerPreviewView(player: model.player)
                    .onTapGesture { model.togglePlay() }
            }
            if model.isExporting {
                Color.black.opacity(0.4)
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text(model.isPreviewExport ? L10n.tr("export.renderingPreview") : L10n.tr("export.exporting"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.togglePlay()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EditorChrome.text)
                        .frame(width: 28, height: 28)
                        .background(EditorChrome.play, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(model.duration <= 0 || model.isExporting || model.previewPlayer != nil)
                .help(model.isPlaying ? L10n.tr("common.pause") : L10n.tr("common.play"))

                Text("\(MediaProbe.formatClock(model.currentTime))  /  \(MediaProbe.formatClock(model.trimDuration))")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(EditorChrome.text)

                Spacer()

                Text(L10n.tr("editor.in", MediaProbe.formatClock(model.trimStart)))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(EditorChrome.label)
                Text(L10n.tr("editor.out", MediaProbe.formatClock(model.trimEnd)))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(EditorChrome.label)

                if model.isTrimmed {
                    Button(L10n.tr("common.reset")) { model.resetTrim() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(EditorChrome.export)
                        .disabled(model.isExporting)
                }
            }

            TrimTimelineView(
                start: Binding(
                    get: { model.trimStart },
                    set: { model.setTrimStart($0) }
                ),
                end: Binding(
                    get: { model.trimEnd },
                    set: { model.setTrimEnd($0) }
                ),
                current: Binding(
                    get: { model.currentTime },
                    set: { model.seek(to: $0) }
                ),
                duration: model.duration,
                filmstrip: model.filmstrip,
                onSeek: {
                    if model.isPlaying { model.pause() }
                    model.seek(to: $0)
                },
                onChangeStart: { model.setTrimStart($0) },
                onChangeEnd: { model.setTrimEnd($0) }
            )
            .opacity(model.duration > 0 ? 1 : 0.4)
            .disabled(model.duration <= 0 || model.isExporting || model.previewPlayer != nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(EditorChrome.window)
    }
}
