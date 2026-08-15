import AppKit
import SwiftUI

struct FilesListView: View {
    @ObservedObject var appState: AppState
    @State private var selection: String?
    /// Empty = default (date desc) with no header indicator.
    @State private var sortOrder: [KeyPathComparator<RecordingEntry>] = []
    /// Consecutive header clicks on the same column (1 → 2 → 3 restores default).
    @State private var sortCycleStep = 0
    @State private var sortCycleKey: AnyKeyPath?
    @State private var suppressSortCycleHandling = false
    @State private var revealSelectionNonce = 0
    @State private var renamingPath: String?
    @State private var renameDraft = ""
    /// Suppress focus-loss commit while switching rename from one cell to another.
    @State private var ignoreRenameFocusLoss = false
    @FocusState private var renameFieldFocused: Bool

    /// OMI-like list chrome; keep column ideals tight so 820-wide window has no H-scroll.
    private static let bodyFont = Font.system(size: 12.5)
    private static let thumbSize = CGSize(width: 52, height: 30)
    private static let rowHeight: CGFloat = 42
    private static let defaultSort: [KeyPathComparator<RecordingEntry>] = [
        KeyPathComparator(\RecordingEntry.date, order: .reverse)
    ]

    private var sortedRecordings: [RecordingEntry] {
        appState.recordings.sorted(using: sortOrder.isEmpty ? Self.defaultSort : sortOrder)
    }

    private var isRenaming: Bool { renamingPath != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if appState.recordings.isEmpty {
                ContentUnavailableView(
                    L10n.tr("files.emptyTitle"),
                    systemImage: "film",
                    description: Text(L10n.tr("files.emptyDescription"))
                )
            } else {
                table
                    .frame(minHeight: 0, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 0, minHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            selection = appState.highlightPath ?? sortedRecordings.first?.path
            Task { await appState.refreshRecordings() }
        }
        .onChange(of: appState.highlightPath) { _, newValue in
            if let newValue {
                selection = newValue
            }
        }
        .onChange(of: appState.recordings) { _, list in
            if selection == nil {
                selection = appState.highlightPath ?? list.sorted(using: sortOrder.isEmpty ? Self.defaultSort : sortOrder).first?.path
            }
        }
        .onChange(of: selection) { _, newValue in
            if let renamingPath, renamingPath != newValue {
                commitRename()
            }
        }
        .onChange(of: sortOrder) { _, newOrder in
            handleSortOrderChange(newOrder)
        }
        .onChange(of: renameFieldFocused) { _, focused in
            // Losing focus commits — but not when we intentionally switch rename targets.
            if !focused, renamingPath != nil, !ignoreRenameFocusLoss {
                commitRename()
            }
        }
    }

    private var header: some View {
        HStack {
            Text(L10n.tr("files.title"))
                .font(.headline)
            Spacer()
            Button(L10n.tr("common.showInFinder")) {
                NSWorkspace.shared.open(RecordingsLibrary.directoryURL)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var table: some View {
        Table(sortedRecordings, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(L10n.tr("common.name"), value: \.name) { entry in
                HStack(spacing: 8) {
                    RecordingThumbnailView(path: entry.path, size: Self.thumbSize)
                    nameCell(for: entry)
                }
            }
            .width(min: 200, ideal: 280, max: .infinity)
            .alignment(.leading)

            TableColumn(L10n.tr("files.duration"), value: \.duration) { entry in
                Text(entry.formattedDuration)
                    .font(Self.bodyFont.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(78)
            .alignment(.leading)

            TableColumn(L10n.tr("files.size"), value: \.size) { entry in
                Text(entry.formattedSize)
                    .font(Self.bodyFont)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(64)
            .alignment(.leading)

            TableColumn(L10n.tr("files.type"), value: \.kind) { entry in
                Text(entry.kind.displayName)
                    .font(Self.bodyFont)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(64)
            .alignment(.leading)

            TableColumn(L10n.tr("files.date"), value: \.date) { entry in
                Text(entry.formattedDate)
                    .font(Self.bodyFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(136)
            .alignment(.leading)

            TableColumn(L10n.tr("files.operation")) { entry in
                HStack(spacing: 4) {
                    OperationIconButton(
                        systemName: "eye.circle",
                        tooltip: L10n.tr("common.preview"),
                        action: { quickLook(entry.path) }
                    )
                    OperationIconButton(
                        systemName: "play.circle",
                        tooltip: L10n.tr("common.play"),
                        action: { play(entry.path) }
                    )
                    OperationIconButton(
                        systemName: "slider.horizontal.2.square.on.square",
                        tooltip: L10n.tr("common.edit"),
                        action: { appState.showEditor(entry) }
                    )
                }
            }
            .width(108)
            .alignment(.center)
        }
        .font(Self.bodyFont)
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .scrollIndicators(.visible, axes: .vertical)
        .contextMenu(forSelectionType: String.self) { paths in
            if let path = paths.first,
               let entry = appState.recordings.first(where: { $0.path == path }) {
                entryContextMenu(entry)
            }
        }
        .background(
            TableChromeInstaller(
                rowHeight: Self.rowHeight,
                isRenaming: isRenaming,
                selectionPath: selection,
                sortedPaths: sortedRecordings.map(\.path),
                revealNonce: revealSelectionNonce,
                onDoubleClick: {
                    if let selection { quickLook(selection) }
                },
                onSpace: {
                    if let selection { quickLook(selection) }
                },
                onReturn: {
                    if let path = selection,
                       let entry = appState.recordings.first(where: { $0.path == path }) {
                        beginRename(entry)
                    }
                },
                onDelete: {
                    if let path = selection,
                       let entry = appState.recordings.first(where: { $0.path == path }) {
                        confirmMoveToTrash(entry)
                    }
                },
                onRightClickRow: { path in
                    if selection != path { selection = path }
                }
            )
        )
    }

    @ViewBuilder
    private func entryContextMenu(_ entry: RecordingEntry) -> some View {
        Button(L10n.tr("common.preview")) { quickLook(entry.path) }
        Button(L10n.tr("common.edit")) { appState.showEditor(entry) }
        Divider()
        Button(L10n.tr("common.play")) { play(entry.path) }
        Button(L10n.tr("files.convertCompress")) {}
            .disabled(true)
        Divider()
        Button(L10n.tr("common.rename")) { beginRename(entry) }
        Button(L10n.tr("common.showInFinder")) { try? RecordingsLibrary.revealInFinder(path: entry.path) }
        Button(L10n.tr("common.delete"), role: .destructive) { confirmMoveToTrash(entry) }
    }

    @ViewBuilder
    private func nameCell(for entry: RecordingEntry) -> some View {
        if renamingPath == entry.path {
            TextField(L10n.tr("common.name"), text: $renameDraft)
                .font(Self.bodyFont)
                .textFieldStyle(.plain)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    Rectangle()
                        .strokeBorder(Color(nsColor: .selectedControlColor), lineWidth: 1)
                )
                .focused($renameFieldFocused)
                .onSubmit { commitRename() }
                .onExitCommand { cancelRename() }
                .onAppear {
                    renameFieldFocused = true
                }
        } else {
            Text(entry.name)
                .font(Self.bodyFont)
                .fontWeight(entry.path == appState.highlightPath ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// SwiftUI Table only toggles asc↔desc; third consecutive click restores default (no indicator).
    private func handleSortOrderChange(_ newOrder: [KeyPathComparator<RecordingEntry>]) {
        if suppressSortCycleHandling {
            suppressSortCycleHandling = false
            scheduleRevealSelection()
            return
        }
        guard let key = newOrder.first?.keyPath else {
            restoreDefaultSort()
            return
        }
        if sortCycleKey == key {
            sortCycleStep += 1
        } else {
            sortCycleKey = key
            sortCycleStep = 1
        }
        if sortCycleStep >= 3 {
            restoreDefaultSort()
            return
        }
        scheduleRevealSelection()
    }

    private func restoreDefaultSort() {
        sortCycleKey = nil
        sortCycleStep = 0
        if sortOrder.isEmpty {
            scheduleRevealSelection()
            return
        }
        suppressSortCycleHandling = true
        sortOrder = []
        // reveal runs via the suppressed onChange path
    }

    private func scheduleRevealSelection() {
        guard selection != nil else { return }
        revealSelectionNonce &+= 1
    }

    private func beginRename(_ entry: RecordingEntry) {
        if renamingPath == entry.path {
            renameFieldFocused = true
            return
        }
        if renamingPath != nil {
            ignoreRenameFocusLoss = true
            commitRename()
        }
        renamingPath = entry.path
        renameDraft = entry.name
        DispatchQueue.main.async {
            renameFieldFocused = true
            ignoreRenameFocusLoss = false
        }
    }

    private func cancelRename() {
        renamingPath = nil
        renameDraft = ""
        renameFieldFocused = false
    }

    private func commitRename() {
        guard let path = renamingPath else { return }
        let draft = renameDraft
        // Clear editing state first so selection onChange does not re-enter commit.
        renamingPath = nil
        renameFieldFocused = false

        let cleaned = RecordingsLibrary.sanitizeBaseName(draft)
        if cleaned.isEmpty {
            renameDraft = ""
            return
        }
        if let entry = appState.recordings.first(where: { $0.path == path }), entry.name == cleaned {
            return
        }

        do {
            let newPath = try RecordingsLibrary.rename(path: path, to: cleaned)
            if selection == nil || selection == path {
                selection = newPath
            }
            if appState.highlightPath == path {
                appState.highlightPath = newPath
            }
            Task { await appState.refreshRecordings() }
        } catch {
            presentError(error, title: L10n.tr("files.couldNotRename"))
        }
    }

    private func confirmMoveToTrash(_ entry: RecordingEntry) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("files.moveToTrashTitle")
        alert.informativeText = L10n.tr("files.moveToTrashBody", entry.name)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("files.moveToTrash"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try RecordingsLibrary.delete(path: entry.path)
            Task { await appState.refreshRecordings() }
        } catch {
            presentError(error, title: L10n.tr("files.couldNotTrash"))
        }
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
            let neighbors = sortedRecordings.map(\.path)
            try RecordingsLibrary.quickLook(path: path, neighbors: neighbors)
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error, title: String = L10n.tr("files.couldNotOpen")) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
