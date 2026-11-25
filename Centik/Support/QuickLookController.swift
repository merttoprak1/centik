import AppKit
import QuickLookUI

/// Presents native macOS Quick Look previews for one or more shelved files.
@MainActor
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private var previewURLs: [URL] = []

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func toggle(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if isVisible, previewURLs == urls {
            close()
            return
        }
        preview(urls: urls)
    }

    func preview(urls: [URL]) {
        guard !urls.isEmpty else { return }
        previewURLs = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        if !panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared().orderOut(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { previewURLs.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            guard previewURLs.indices.contains(index) else { return nil }
            return previewURLs[index] as NSURL
        }
    }
}
