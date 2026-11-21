import AppKit
import QuickLookThumbnailing
import SwiftUI

@MainActor
final class ThumbnailLoader: ObservableObject {
    @Published var image: NSImage?

    private var token = UUID()
    private var loadedPath: String?

    func load(_ item: ShelfItem, side: CGFloat) {
        guard let url = item.resolvedURL, !item.isMissing else {
            image = NSImage(systemSymbolName: "questionmark.folder", accessibilityDescription: nil)
            loadedPath = nil
            return
        }
        if loadedPath == url.path, image != nil { return }
        loadedPath = url.path
        let requestToken = UUID()
        token = requestToken

        let fallback = NSWorkspace.shared.icon(forFile: url.path)
        fallback.size = NSSize(width: side, height: side)
        image = fallback

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side * 2, height: side * 2),
            scale: scale,
            representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let representation else { return }
            let cgImage = representation.cgImage
            let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: side, height: side))
            Task { @MainActor in
                guard let self, self.token == requestToken else { return }
                self.image = thumbnail
            }
        }
    }
}
