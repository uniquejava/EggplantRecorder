import AppKit
import SwiftUI

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            preview
            Divider()
            controls
        }
        .frame(minWidth: 720, minHeight: 460)
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.space, phases: .down) { _ in
            model.togglePlay()
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
            let step: TimeInterval = press.modifiers.contains(.option) ? 0.1 : 1
            model.skip(press.key == .leftArrow ? -step : step)
            return .handled
        }
        .alert("Could not export", isPresented: alertPresented) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
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

    private var header: some View {
        HStack(spacing: 12) {
            Text(model.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            if model.isExporting {
                ProgressView(value: model.exportProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 140)
                Text("Exporting…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button("Export") {
                model.export()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(model.isExporting || model.duration <= 0 || model.loadFailed)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var preview: some View {
        ZStack {
            Color.black
            if model.loadFailed {
                ContentUnavailableView(
                    "Could not open recording",
                    systemImage: "exclamationmark.triangle",
                    description: Text(model.name)
                )
                .foregroundStyle(.white)
            } else {
                PlayerPreviewView(player: model.player)
                    .onTapGesture { model.togglePlay() }
                if model.isExporting {
                    Color.black.opacity(0.35)
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
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
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(model.duration <= 0 || model.isExporting)
                .help(model.isPlaying ? "Pause" : "Play")

                Text("\(MediaProbe.formatClock(model.currentTime))  /  \(MediaProbe.formatClock(model.trimDuration))")
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Text("In \(MediaProbe.formatClock(model.trimStart))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("Out \(MediaProbe.formatClock(model.trimEnd))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)

                if model.isTrimmed {
                    Button("Reset") { model.resetTrim() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
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
            .disabled(model.duration <= 0 || model.isExporting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
