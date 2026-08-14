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

/// AppKit hooks that SwiftUI Table does not expose (row height + double-click).
/// Avoid touching column widths / intercell spacing — that desyncs headers from cells.
struct TableChromeInstaller: NSViewRepresentable {
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
            // Overlay scrollers do not steal column width (legacy scrollers desync header vs rows).
            if let scrollView = table.enclosingScrollView {
                scrollView.hasHorizontalScroller = false
                scrollView.horizontalScrollElasticity = .none
                scrollView.scrollerStyle = .overlay
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
