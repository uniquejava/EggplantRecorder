import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 400)
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject private var prefs = AppPreferences.shared

    private let labelWidth: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsRow(label: "Save folder:") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                        Text(prefs.libraryFolderDisplayPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Menu {
                            Button("Choose…") { prefs.chooseLibraryFolder() }
                            Button("Reveal in Finder") { prefs.revealLibraryFolder() }
                            if !prefs.libraryFolderPath.isEmpty {
                                Divider()
                                Button("Reset to Default") { prefs.resetLibraryFolder() }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()

                        Button {
                            prefs.revealLibraryFolder()
                        } label: {
                            Image(systemName: "arrow.forward.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.yellow, .orange)
                        }
                        .buttonStyle(.plain)
                        .help("Open save folder")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                    Text("Recordings are saved here by default.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            settingsRow(label: "When recording:") {
                Toggle("Show recording time", isOn: $prefs.displayRecordingTime)
                    .toggleStyle(.checkbox)
            }

            settingsRow(label: "After recording:") {
                Toggle("Open Files List", isOn: $prefs.openFilesListAfterRecording)
                    .toggleStyle(.checkbox)
            }

            settingsRow(label: "After editing:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Open Files List", isOn: $prefs.openFilesListAfterEditing)
                        .toggleStyle(.checkbox)
                    Toggle("Reveal in Finder", isOn: $prefs.openFolderAfterEditing)
                        .toggleStyle(.checkbox)
                    Toggle("Delete original video", isOn: $prefs.deleteOriginalAfterEditing)
                        .toggleStyle(.checkbox)
                }
            }

            settingsRow(label: "Dock icon:") {
                Toggle("Hide", isOn: $prefs.hideDockIcon)
                    .toggleStyle(.checkbox)
            }

            settingsRow(label: "Capture defaults:") {
                HStack(spacing: 10) {
                    compactPicker("Resolution", selection: $prefs.defaultResolution) {
                        ForEach(CaptureResolution.allCases) { pick in
                            Text(pick.label).tag(pick)
                        }
                    }
                    compactPicker("Frame rate", selection: $prefs.defaultFrameRate) {
                        ForEach(CaptureFrameRate.allCases) { pick in
                            Text(pick.label).tag(pick)
                        }
                    }
                    compactPicker("Countdown", selection: $prefs.defaultCountdown) {
                        ForEach(CaptureCountdown.allCases) { pick in
                            Text(pick.label).tag(pick)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            settingsRow(label: "Edit defaults:") {
                HStack(spacing: 10) {
                    compactPicker("Preview", selection: $prefs.editPreviewSeconds) {
                        Text("15s").tag(15)
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                    }
                    compactPicker("Quality", selection: $prefs.defaultExportQuality) {
                        ForEach(ExportSettings.Quality.allCases) { pick in
                            Text(pick.title).tag(pick)
                        }
                    }
                    compactPicker("Audio", selection: $prefs.defaultExportAudioChannels) {
                        ForEach(ExportSettings.AudioChannels.allCases) { pick in
                            Text(pick.title).tag(pick)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func settingsRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .multilineTextAlignment(.trailing)
                .frame(width: labelWidth, alignment: .trailing)
                .padding(.top, 3)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func compactPicker<Selection: Hashable, Content: View>(
        _ title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Picker("", selection: selection) {
                content()
            }
            .labelsHidden()
            .frame(width: 108)
        }
    }
}
