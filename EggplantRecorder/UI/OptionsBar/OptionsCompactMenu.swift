import AppKit
import SwiftUI

struct OptionsMenuItem: Identifiable {
    let id: String
    let title: String
    var isSelected: Bool = false
}

/// Panel trigger + AppKit `NSMenu` so popup option rows can use a compact font.
/// (SwiftUI `Menu` / system menus ignore SwiftUI `.font` on items.)
struct OptionsCompactMenuTrigger: View {
    let title: String
    let items: [OptionsMenuItem]
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay {
            OptionsCompactMenuAnchor(items: items, onSelect: onSelect)
        }
    }
}

/// Invisible AppKit view that owns mouse-down → compact `NSMenu`.
private struct OptionsCompactMenuAnchor: NSViewRepresentable {
    let items: [OptionsMenuItem]
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> OptionsCompactMenuNSView {
        let view = OptionsCompactMenuNSView()
        view.items = items
        view.onSelect = onSelect
        return view
    }

    func updateNSView(_ nsView: OptionsCompactMenuNSView, context: Context) {
        nsView.items = items
        nsView.onSelect = onSelect
    }
}

private final class OptionsCompactMenuNSView: NSView {
    var items: [OptionsMenuItem] = []
    var onSelect: ((String) -> Void)?

    private let menuTarget = OptionsCompactMenuTarget()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        menuTarget.owner = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Receive clicks over the SwiftUI label.
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard !items.isEmpty else { return }

        let menu = NSMenu()
        // Compact option rows — this is what SwiftUI `Menu` cannot shrink.
        menu.font = NSFont.systemFont(ofSize: 11)
        menu.autoenablesItems = false

        for item in items {
            let mi = NSMenuItem(
                title: item.title,
                action: #selector(OptionsCompactMenuTarget.pick(_:)),
                keyEquivalent: ""
            )
            mi.target = menuTarget
            mi.representedObject = item.id
            mi.state = item.isSelected ? .on : .off
            mi.isEnabled = true
            menu.addItem(mi)
        }

        // Open just under the trigger.
        let point = NSPoint(x: 0, y: bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: self)
    }
}

private final class OptionsCompactMenuTarget: NSObject {
    weak var owner: OptionsCompactMenuNSView?

    @objc func pick(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        owner?.onSelect?(id)
    }
}
