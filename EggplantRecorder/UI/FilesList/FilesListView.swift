import AppKit
import SwiftUI

struct FilesListView: View {
    @ObservedObject var appState: AppState
    @State private var selection: String?
    @State private var confirmDelete: RecordingEntry?

    /// OMI-like list chrome; keep column ideals ≤ ~760 so 800-wide window has no H-scroll.
    private static let bodyFont = Font.system(size: 12.5)
    private static let thumbSize = CGSize(width: 52, height: 30)
    private static let rowHeight: CGFloat = 42

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if appState.recordings.isEmpty {
                ContentUnavailableView(
                    "No recordings yet",
                    systemImage: "film",
                    description: Text("Stop a recording to see it here. Library: ~/Movies/EggplantRecorder")
                )
            } else {
                table
            }
        }
        .frame(minWidth: 0, minHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            selection = appState.highlightPath ?? appState.recordings.first?.path
            Task { await appState.refreshRecordings() }
        }
        .onChange(of: appState.highlightPath) { _, newValue in
            if let newValue {
                selection = newValue
            }
        }
        .onChange(of: appState.recordings) { _, list in
            if selection == nil {
                selection = appState.highlightPath ?? list.first?.path
            }
        }
        .alert(
            "Delete recording?",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            presenting: confirmDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                try? RecordingsLibrary.delete(path: entry.path)
                Task { await appState.refreshRecordings() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("Move “\(entry.name)” to trash? This cannot be undone from here.")
        }
    }

    private var header: some View {
        HStack {
            Text("Files List")
                .font(.headline)
            Spacer()
            Button("Reveal Library") {
                NSWorkspace.shared.open(RecordingsLibrary.directoryURL)
            }
            Button("Refresh") {
                Task { await appState.refreshRecordings() }
            }
            .help("Reload recordings from ~/Movies/EggplantRecorder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var table: some View {
        Table(appState.recordings, selection: $selection) {
            TableColumn("Name") { entry in
                HStack(spacing: 8) {
                    RecordingThumbnailView(path: entry.path, size: Self.thumbSize)
                    Text(entry.name)
                        .font(Self.bodyFont)
                        .fontWeight(entry.path == appState.highlightPath ? .semibold : .regular)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .width(min: 200, ideal: 280, max: .infinity)
            .alignment(.leading)

            TableColumn("Duration") { entry in
                Text(entry.formattedDuration)
                    .font(Self.bodyFont.monospacedDigit())
            }
            .width(78)
            .alignment(.leading)

            TableColumn("Size") { entry in
                Text(entry.formattedSize)
                    .font(Self.bodyFont)
            }
            .width(64)
            .alignment(.leading)

            TableColumn("Type") { entry in
                Text(entry.kind.displayName)
                    .font(Self.bodyFont)
            }
            .width(64)
            .alignment(.leading)

            TableColumn("Date") { entry in
                Text(entry.formattedDate)
                    .font(Self.bodyFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(136)
            .alignment(.leading)

            TableColumn("Operation") { entry in
                HStack(spacing: 4) {
                    OperationIconButton(
                        systemName: "eye.circle",
                        tooltip: "Preview",
                        action: { quickLook(entry.path) }
                    )
                    OperationIconButton(
                        systemName: "play.circle",
                        tooltip: "Play",
                        action: { play(entry.path) }
                    )
                }
            }
            .width(84)
            .alignment(.center)
        }
        .font(Self.bodyFont)
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: String.self) { paths in
            if let path = paths.first {
                Button("Preview") { quickLook(path) }
                Button("Edit") {}
                    .disabled(true)
                Divider()
                Button("Play") { play(path) }
                Button("Convert/Compress") {}
                    .disabled(true)
                Divider()
                Button("Rename") {}
                    .disabled(true)
                Button("Show in Finder") { try? RecordingsLibrary.revealInFinder(path: path) }
                Button("Remove from List") {}
                    .disabled(true)
                Button("Delete", role: .destructive) {
                    if let entry = appState.recordings.first(where: { $0.path == path }) {
                        confirmDelete = entry
                    }
                }
            }
        } primaryAction: { paths in
            if let path = paths.first {
                quickLook(path)
            }
        }
        .background(
            TableChromeInstaller(rowHeight: Self.rowHeight) {
                if let selection {
                    quickLook(selection)
                }
            }
        )
    }

    private func play(_ path: String) {
        do {
            try RecordingsLibrary.play(path: path)
        } catch {
            presentError(error)
        }
    }

    private func quickLook(_ path: String) {
        do {
            let neighbors = appState.recordings.map(\.path)
            try RecordingsLibrary.quickLook(path: path, neighbors: neighbors)
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not open recording"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
