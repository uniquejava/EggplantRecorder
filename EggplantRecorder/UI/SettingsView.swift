import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem {
                    Label(L10n.tr("settings.general"), systemImage: "gearshape")
                }

            AboutView()
                .tabItem {
                    Label(L10n.tr("settings.about"), systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 440)
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var selectedLanguage = AppLanguage.preference

    private let labelWidth: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsRow(label: L10n.tr("settings.language") + ":") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("", selection: $selectedLanguage) {
                        ForEach(AppLanguagePreference.allCases) { preference in
                            Text(preference.menuTitle).tag(preference)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200, alignment: .leading)
                    .onChange(of: selectedLanguage) { _, newValue in
                        AppLanguage.setPreferenceAndRelaunch(newValue)
                    }

                    Text(L10n.tr("settings.language.hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            settingsRow(label: L10n.tr("settings.saveFolder")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)
                        Text(prefs.libraryFolderDisplayPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Menu {
                            Button(L10n.tr("common.chooseEllipsis")) { prefs.chooseLibraryFolder() }
                            Button(L10n.tr("common.revealInFinder")) { prefs.revealLibraryFolder() }
                            if !prefs.libraryFolderPath.isEmpty {
                                Divider()
                                Button(L10n.tr("settings.resetDefault")) { prefs.resetLibraryFolder() }
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
                        .help(L10n.tr("settings.openSaveFolder"))
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

                    Text(L10n.tr("settings.saveFolderHint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            settingsRow(label: L10n.tr("settings.whenRecording")) {
                Toggle(L10n.tr("settings.showRecordingTime"), isOn: $prefs.displayRecordingTime)
                    .toggleStyle(.checkbox)
            }

            settingsRow(label: L10n.tr("settings.afterRecording")) {
                Toggle(L10n.tr("settings.openFilesList"), isOn: $prefs.openFilesListAfterRecording)
                    .toggleStyle(.checkbox)
            }

            settingsRow(label: L10n.tr("settings.afterEditing")) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L10n.tr("settings.openFilesList"), isOn: $prefs.openFilesListAfterEditing)
                        .toggleStyle(.checkbox)
                    Toggle(L10n.tr("common.revealInFinder"), isOn: $prefs.openFolderAfterEditing)
                        .toggleStyle(.checkbox)
                    Toggle(L10n.tr("settings.deleteOriginal"), isOn: $prefs.deleteOriginalAfterEditing)
                        .toggleStyle(.checkbox)
                }
            }

            settingsRow(label: L10n.tr("settings.dockIcon")) {
                Toggle(L10n.tr("common.hide"), isOn: $prefs.hideDockIcon)
                    .toggleStyle(.checkbox)
            }

            settingsRow(label: L10n.tr("settings.captureDefaults")) {
                HStack(spacing: 10) {
                    compactPicker(L10n.tr("settings.resolution"), selection: $prefs.defaultResolution) {
                        ForEach(CaptureResolution.allCases) { pick in
                            Text(pick.label).tag(pick)
                        }
                    }
                    compactPicker(L10n.tr("settings.frameRate"), selection: $prefs.defaultFrameRate) {
                        ForEach(CaptureFrameRate.allCases) { pick in
                            Text(pick.label).tag(pick)
                        }
                    }
                    compactPicker(L10n.tr("settings.countdown"), selection: $prefs.defaultCountdown) {
                        ForEach(CaptureCountdown.allCases) { pick in
                            Text(pick.label).tag(pick)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            settingsRow(label: L10n.tr("settings.editDefaults")) {
                HStack(spacing: 10) {
                    compactPicker(L10n.tr("settings.preview"), selection: $prefs.editPreviewSeconds) {
                        Text("15s").tag(15)
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                    }
                    compactPicker(L10n.tr("settings.quality"), selection: $prefs.defaultExportQuality) {
                        ForEach(ExportSettings.Quality.allCases) { pick in
                            Text(pick.title).tag(pick)
                        }
                    }
                    compactPicker(L10n.tr("settings.audio"), selection: $prefs.defaultExportAudioChannels) {
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
        .onAppear {
            selectedLanguage = AppLanguage.preference
        }
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
