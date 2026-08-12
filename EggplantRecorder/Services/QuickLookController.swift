import AppKit
import Quartz

/// Finder-style Quick Look via `QLPreviewPanel`.
///
/// Apple requires setup only inside `beginPreviewPanelControl:` after the panel
/// acquires a controller from the responder chain — never set `delegate` /
/// `dataSource` / `currentPreviewItemIndex` beforehand.
/// See `QLPreviewPanel.h`.
@MainActor
final class QuickLookController: NSResponder, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private var items: [URL] = []
    private var focusIndex = 0
    private var installedInResponderChain = false

    func install() {
        guard !installedInResponderChain else { return }
        nextResponder = NSApp.nextResponder
        NSApp.nextResponder = self
        installedInResponderChain = true
    }

    func preview(path: String, neighbors: [String] = []) {
        install()

        let focus = URL(fileURLWithPath: path)
        let neighborURLs = neighbors.map { URL(fileURLWithPath: $0) }
        if neighborURLs.isEmpty {
            items = [focus]
        } else {
            items = neighborURLs
        }

        if let index = items.firstIndex(of: focus) {
            focusIndex = index
        } else {
            items.insert(focus, at: 0)
            focusIndex = 0
        }

        NSApp.activate(ignoringOtherApps: true)

        guard let panel = QLPreviewPanel.shared() else { return }

        // Do not touch delegate/dataSource/index here — only after we become controller.
        if panel.isVisible, panel.currentController != nil {
            panel.reloadData()
            panel.currentPreviewItemIndex = focusIndex
        } else {
            panel.makeKeyAndOrderFront(nil)
            // Responder chain may need an explicit refresh for menu-bar apps.
            panel.updateController()
            if panel.currentController != nil {
                panel.reloadData()
                panel.currentPreviewItemIndex = focusIndex
            }
        }
    }

    // MARK: - QLPreviewPanelController (responder chain)

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        !items.isEmpty
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = focusIndex
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> (any QLPreviewItem)? {
        guard items.indices.contains(index) else { return nil }
        return items[index] as NSURL
    }
}
