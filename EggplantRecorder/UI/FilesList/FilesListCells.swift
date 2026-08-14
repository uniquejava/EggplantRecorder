import AppKit
import SwiftUI

/// AppKit button so `toolTip` actually shows inside SwiftUI `Table` cells.
struct OperationIconButton: NSViewRepresentable {
    let systemName: String
    let tooltip: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = RightClickForwardingButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
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

/// SwiftUI Table's row context menu never sees right-clicks that NSButton swallows.
private final class RightClickForwardingButton: NSButton {
    override func rightMouseDown(with event: NSEvent) {
        nextResponder?.rightMouseDown(with: event)
    }
}

struct RecordingThumbnailView: View {
    let path: String
    let size: CGSize
    @State private var image: NSImage?

    var body: some View {
        // Fixed layout box — never let NSImage / video aspect ratio leak into
        // Table cell intrinsic width (Area clips are often non-16:9 / portrait).
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.25))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "film")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .fixedSize()
        .task(id: path) {
            image = await MediaProbe.thumbnail(of: URL(fileURLWithPath: path))
        }
    }
}

/// AppKit hooks that SwiftUI Table does not expose (row height, double-click, Space/Return/Delete).
/// Avoid touching column widths / intercell spacing — that desyncs headers from cells.
/// Do not steal `table.target` / `doubleAction` — that breaks header hit-testing with SwiftUI Table.
struct TableChromeInstaller: NSViewRepresentable {
    var rowHeight: CGFloat
    /// When true, Space/Return/Delete are left to the rename field.
    var isRenaming: Bool
    var selectionPath: String?
    var sortedPaths: [String]
    /// Bump after sort so the selected row is scrolled into view if needed.
    var revealNonce: Int
    var onDoubleClick: () -> Void
    var onSpace: () -> Void
    var onReturn: () -> Void
    var onDelete: () -> Void
    var onRightClickRow: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            rowHeight: rowHeight,
            isRenaming: isRenaming,
            selectionPath: selectionPath,
            sortedPaths: sortedPaths,
            revealNonce: revealNonce,
            onDoubleClick: onDoubleClick,
            onSpace: onSpace,
            onReturn: onReturn,
            onDelete: onDelete,
            onRightClickRow: onRightClickRow
        )
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
        let shouldReveal = context.coordinator.revealNonce != revealNonce
        context.coordinator.rowHeight = rowHeight
        context.coordinator.isRenaming = isRenaming
        context.coordinator.selectionPath = selectionPath
        context.coordinator.sortedPaths = sortedPaths
        context.coordinator.revealNonce = revealNonce
        context.coordinator.onDoubleClick = onDoubleClick
        context.coordinator.onSpace = onSpace
        context.coordinator.onReturn = onReturn
        context.coordinator.onDelete = onDelete
        context.coordinator.onRightClickRow = onRightClickRow
        DispatchQueue.main.async {
            context.coordinator.install(from: nsView)
            if shouldReveal {
                DispatchQueue.main.async {
                    context.coordinator.revealSelectionIfNeeded()
                }
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator: NSObject {
        var rowHeight: CGFloat
        var isRenaming: Bool
        var selectionPath: String?
        var sortedPaths: [String]
        var revealNonce: Int
        var onDoubleClick: () -> Void
        var onSpace: () -> Void
        var onReturn: () -> Void
        var onDelete: () -> Void
        var onRightClickRow: (String) -> Void
        private weak var hookedTable: NSTableView?
        private var keyMonitor: Any?
        private var clickMonitor: Any?

        init(
            rowHeight: CGFloat,
            isRenaming: Bool,
            selectionPath: String?,
            sortedPaths: [String],
            revealNonce: Int,
            onDoubleClick: @escaping () -> Void,
            onSpace: @escaping () -> Void,
            onReturn: @escaping () -> Void,
            onDelete: @escaping () -> Void,
            onRightClickRow: @escaping (String) -> Void
        ) {
            self.rowHeight = rowHeight
            self.isRenaming = isRenaming
            self.selectionPath = selectionPath
            self.sortedPaths = sortedPaths
            self.revealNonce = revealNonce
            self.onDoubleClick = onDoubleClick
            self.onSpace = onSpace
            self.onReturn = onReturn
            self.onDelete = onDelete
            self.onRightClickRow = onRightClickRow
        }

        func install(from sentinel: NSView) {
            if hookedTable == nil || hookedTable?.window == nil {
                guard let root = sentinel.window?.contentView ?? sentinel.superview else { return }
                guard let table = Self.findTableView(in: root) else { return }
                hookedTable = table
                if table.target === self {
                    table.target = nil
                    table.doubleAction = nil
                }
                installMonitorsIfNeeded()
            }
            guard let table = hookedTable else { return }
            if table.rowHeight != rowHeight {
                table.rowHeight = rowHeight
            }
            table.usesAlternatingRowBackgroundColors = true
            configureScrollers(table.enclosingScrollView)
        }

        /// Legacy vertical scroller stays on screen. Overlay bars always fade, which
        /// is why `autohidesScrollers = false` alone looked like a no-op.
        private func configureScrollers(_ scrollView: NSScrollView?) {
            guard let scrollView else { return }
            if scrollView.hasHorizontalScroller {
                scrollView.hasHorizontalScroller = false
                scrollView.horizontalScrollElasticity = .none
            }
            if !scrollView.hasVerticalScroller {
                scrollView.hasVerticalScroller = true
            }
            if scrollView.scrollerStyle != .legacy {
                scrollView.scrollerStyle = .legacy
            }
            if scrollView.autohidesScrollers {
                scrollView.autohidesScrollers = false
            }
        }

        func teardown() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            if let clickMonitor {
                NSEvent.removeMonitor(clickMonitor)
                self.clickMonitor = nil
            }
        }

        /// Scroll only when the selected row is not fully inside the visible rect.
        func revealSelectionIfNeeded() {
            guard let table = hookedTable, let path = selectionPath else { return }
            guard let row = sortedPaths.firstIndex(of: path), row < table.numberOfRows else { return }
            table.layoutSubtreeIfNeeded()
            let rowRect = table.rect(ofRow: row)
            guard rowRect.height > 0 else { return }
            if table.visibleRect.contains(rowRect) { return }
            table.scrollRowToVisible(row)
        }

        private func installMonitorsIfNeeded() {
            if keyMonitor == nil {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    return self.handleKeyDown(event)
                }
            }
            if clickMonitor == nil {
                clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    guard let self else { return event }
                    self.handleMouseDown(event)
                    return event
                }
            }
        }

        private func handleMouseDown(_ event: NSEvent) {
            guard let table = hookedTable, let window = table.window, event.window === window else { return }
            if event.type == .rightMouseDown {
                guard let path = rowPath(at: event, in: table) else { return }
                onRightClickRow(path)
                return
            }
            guard !isRenaming else { return }
            guard event.clickCount == 2 else { return }
            guard rowPath(at: event, in: table) != nil else { return }
            onDoubleClick()
        }

        private func rowPath(at event: NSEvent, in table: NSTableView) -> String? {
            let windowPoint = event.locationInWindow
            if let header = table.headerView {
                let inHeader = header.convert(windowPoint, from: nil)
                if header.bounds.contains(inHeader) { return nil }
            }
            let tablePoint = table.convert(windowPoint, from: nil)
            let row = table.row(at: tablePoint)
            guard row >= 0, row < sortedPaths.count else { return nil }
            return sortedPaths[row]
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            guard !isRenaming else { return event }
            guard let table = hookedTable, let window = table.window, window.isKeyWindow else {
                return event
            }
            // Don't steal keys from text fields / other controls outside the table.
            if Self.isEditingText(in: window) { return event }
            guard Self.isTableInResponderChain(table, window: window) else { return event }
            // Ignore key repeats and modified shortcuts (e.g. ⌘Space).
            guard !event.isARepeat, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else {
                return event
            }

            switch event.keyCode {
            case 49: // Space
                onSpace()
                return nil
            case 36, 76: // Return / keypad Enter
                onReturn()
                return nil
            case 51, 117: // Delete / Forward Delete
                onDelete()
                return nil
            default:
                return event
            }
        }

        private static func isEditingText(in window: NSWindow) -> Bool {
            guard let responder = window.firstResponder else { return false }
            if responder is NSTextView || responder is NSTextField { return true }
            if let fieldEditor = window.fieldEditor(false, for: nil), responder === fieldEditor {
                return true
            }
            return false
        }

        private static func isTableInResponderChain(_ table: NSTableView, window: NSWindow) -> Bool {
            var node: NSResponder? = window.firstResponder
            while let current = node {
                if current === table { return true }
                if current === table.enclosingScrollView { return true }
                node = current.nextResponder
            }
            // SwiftUI often leaves firstResponder on the window/contentView; still accept
            // when the table is in the key window and no other view is clearly focused.
            if window.firstResponder === window || window.firstResponder === window.contentView {
                return true
            }
            return false
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
