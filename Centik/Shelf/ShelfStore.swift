import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private let persistence = ShelfPersistence()
    private var loaded = false

    func load() {
        items = persistence.load()
        loaded = true
    }

    func save() {
        guard loaded else { return }
        persistence.save(items)
    }

    @discardableResult
    func add(urls: [URL]) -> [UUID] {
        var inserted: [UUID] = []
        for url in urls where url.isFileURL {
            let path = url.standardizedFileURL.path
            if let existing = items.first(where: { $0.resolvedURL?.standardizedFileURL.path == path || $0.pathFallback == path }) {
                moveToFront(existing.id)
                inserted.append(existing.id)
                continue
            }
            let item = persistence.importFile(at: url)
            items.insert(item, at: 0)
            inserted.append(item.id)
        }
        if !inserted.isEmpty {
            save()
        }
        return inserted
    }

    func addImageData(_ data: Data, fileExtension: String) -> UUID? {
        guard let url = persistence.saveImageData(data, fileExtension: fileExtension) else { return nil }
        let ids = add(urls: [url])
        return ids.first
    }

    func remove(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        persistence.deleteStoredCopy(relativePath: item.storedCopyRelativePath)
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        for item in items {
            persistence.deleteStoredCopy(relativePath: item.storedCopyRelativePath)
        }
        items = []
        save()
    }

    func refreshPresence() {
        let refreshed = items.map { persistence.refresh($0) }
        if refreshed != items {
            items = refreshed
            save()
        }
    }

    func open(_ item: ShelfItem) {
        guard let url = item.resolvedURL, !item.isMissing else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        NSWorkspace.shared.open(url)
        if accessing { url.stopAccessingSecurityScopedResource() }
    }

    func reveal(_ item: ShelfItem) {
        guard let url = item.resolvedURL, !item.isMissing else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        NSWorkspace.shared.activateFileViewerSelecting([url])
        if accessing { url.stopAccessingSecurityScopedResource() }
    }

    func dragProvider(for item: ShelfItem) -> NSItemProvider {
        guard let url = item.resolvedURL, !item.isMissing else { return NSItemProvider() }
        _ = url.startAccessingSecurityScopedResource()
        let provider = NSItemProvider(object: url as NSURL)
        provider.suggestedName = url.lastPathComponent
        return provider
    }

    private func moveToFront(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), index != 0 else { return }
        let item = items.remove(at: index)
        items.insert(item, at: 0)
        save()
    }
}

enum DropPayload {
    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return urls
        }
        let legacy = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let paths = pasteboard.propertyList(forType: legacy) as? [String], !paths.isEmpty {
            return paths.map { URL(fileURLWithPath: $0) }
        }
        return []
    }

    static func image(from pasteboard: NSPasteboard) -> (Data, String)? {
        if let data = pasteboard.data(forType: .png), !data.isEmpty {
            return (data, "png")
        }
        let jpeg = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        if let data = pasteboard.data(forType: jpeg), !data.isEmpty {
            return (data, "jpg")
        }
        if let data = pasteboard.data(forType: .tiff), !data.isEmpty {
            return (data, "tiff")
        }
        return nil
    }

    static func hasFileDrag(_ pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types, !types.isEmpty else { return false }
        if types.contains(.fileURL) { return true }
        if types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) { return true }
        if types.contains(.png) || types.contains(.tiff) { return true }
        if types.contains(NSPasteboard.PasteboardType(UTType.jpeg.identifier)) { return true }
        let promises = NSFilePromiseReceiver.readableDraggedTypes()
        return types.contains { promises.contains($0) }
    }
}
