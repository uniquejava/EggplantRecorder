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
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 160, ideal: 240)

            TableColumn("Duration") { entry in
                Text(entry.formattedDuration)
                    .font(Self.bodyFont.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 70, ideal: 76, max: 80)

            TableColumn("Size") { entry in
                Text(entry.formattedSize)
                    .font(Self.bodyFont)
            }
            .width(min: 52, ideal: 60, max: 68)

            TableColumn("Type") { entry in
                Text(entry.kind.displayName)
                    .font(Self.bodyFont)
            }
            .width(min: 52, ideal: 58, max: 68)

            TableColumn("Date") { entry in
                Text(entry.formattedDate)
                    .font(Self.bodyFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 124, ideal: 132, max: 140)

            TableColumn("Operation") { entry in
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
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
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
            .width(min: 72, ideal: 80, max: 88)
        }
        .font(Self.bodyFont)
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

// MARK: - Thumbnail

/// AppKit button so `toolTip` actually shows inside SwiftUI `Table` cells.
private struct OperationIconButton: NSViewRepresentable {
    let systemName: String
    let tooltip: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked(_:))
        button.toolTip = tooltip
        button.setButtonType(.momentaryChange)
        applyImage(to: button)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.toolTip = tooltip
        applyImage(to: button)
    }

    private func applyImage(to button: NSButton) {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        button.image = NSImage(systemSymbolName: systemName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        button.contentTintColor = .labelColor
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func clicked(_ sender: Any?) { action() }
    }
}

private struct RecordingThumbnailView: View {
    let path: String
    let size: CGSize
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.25))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .cornerRadius(3)
            } else {
                Image(systemName: "film")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .task(id: path) {
            image = await MediaProbe.thumbnail(of: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - AppKit table chrome (row height + double-click)

private struct TableChromeInstaller: NSViewRepresentable {
    var rowHeight: CGFloat
    var onDoubleClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(rowHeight: rowHeight, onDoubleClick: onDoubleClick)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        DispatchQueue.main.async {
            context.coordinator.install(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.rowHeight = rowHeight
        context.coordinator.onDoubleClick = onDoubleClick
        DispatchQueue.main.async {
            context.coordinator.install(from: nsView)
        }
    }

    final class Coordinator: NSObject {
        var rowHeight: CGFloat
        var onDoubleClick: () -> Void
        private weak var hookedTable: NSTableView?

        init(rowHeight: CGFloat, onDoubleClick: @escaping () -> Void) {
            self.rowHeight = rowHeight
            self.onDoubleClick = onDoubleClick
        }

        func install(from sentinel: NSView) {
            guard let root = sentinel.window?.contentView ?? sentinel.superview else { return }
            guard let table = Self.findTableView(in: root) else { return }
            table.rowHeight = rowHeight
            table.usesAlternatingRowBackgroundColors = true
            table.intercellSpacing = NSSize(width: 4, height: 1)
            table.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
            if let scrollView = table.enclosingScrollView {
                scrollView.hasHorizontalScroller = false
                scrollView.horizontalScrollElasticity = .none
                scrollView.autohidesScrollers = true
            }
            if hookedTable !== table || table.doubleAction != #selector(doubleClicked(_:)) {
                table.target = self
                table.doubleAction = #selector(doubleClicked(_:))
                hookedTable = table
            }
        }

        @objc func doubleClicked(_ sender: Any?) {
            onDoubleClick()
        }

        private static func findTableView(in root: NSView) -> NSTableView? {
            if let table = root as? NSTableView {
                return table
            }
            for sub in root.subviews {
                if let found = findTableView(in: sub) {
                    return found
                }
            }
            return nil
        }
    }
}
