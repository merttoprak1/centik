import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var isZipping = false
    @Published var removeAfterDrag: Bool {
        didSet {
            UserDefaults.standard.set(removeAfterDrag, forKey: Self.removeAfterDragKey)
        }
    }

    private static let removeAfterDragKey = "centik.removeAfterDrag"
    private let persistence = ShelfPersistence()
    private var loaded = false
    private var lastSelectedID: UUID?

    init() {
        self.removeAfterDrag = UserDefaults.standard.bool(forKey: Self.removeAfterDragKey)
    }

    var validItems: [ShelfItem] {
        items.filter { $0.resolvedURL != nil && !$0.isMissing }
    }

    var selectedValidItems: [ShelfItem] {
        items.filter { selectedIDs.contains($0.id) && $0.resolvedURL != nil && !$0.isMissing }
    }

    func load() {
        items = persistence.load()
        loaded = true
    }

    func save() {
        guard loaded else { return }
        persistence.save(items)
    }

    @discardableResult
    func add(urls: [URL]) async -> [UUID] {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return [] }

        var inserted: [UUID] = []
        var toImport: [URL] = []

        for url in fileURLs {
            let path = url.standardizedFileURL.path
            if let existing = items.first(where: { $0.resolvedURL?.standardizedFileURL.path == path || $0.pathFallback == path }) {
                moveToFront(existing.id)
                inserted.append(existing.id)
            } else {
                toImport.append(url)
            }
        }

        if !toImport.isEmpty {
            let persistence = self.persistence
            let shouldMove = AppPreferences.shared.fileMode == .move
            let imported = await Task.detached(priority: .userInitiated) {
                toImport.map { persistence.importFile(at: $0, moveToShelf: shouldMove) }
            }.value

            for item in imported {
                let path = item.resolvedURL?.standardizedFileURL.path ?? item.pathFallback
                if let path,
                   let existing = items.first(where: { $0.resolvedURL?.standardizedFileURL.path == path || $0.pathFallback == path }) {
                    moveToFront(existing.id)
                    inserted.append(existing.id)
                } else {
                    items.insert(item, at: 0)
                    inserted.append(item.id)
                }
            }
        }

        if !inserted.isEmpty {
            save()
        }
        return inserted
    }

    func addImageData(_ data: Data, fileExtension: String) async -> UUID? {
        let persistence = self.persistence
        let url = await Task.detached(priority: .userInitiated) {
            persistence.saveImageData(data, fileExtension: fileExtension)
        }.value
        guard let url else { return nil }
        let ids = await add(urls: [url])
        return ids.first
    }

    func addWebURL(_ webURL: URL, title: String?) async -> UUID? {
        let persistence = self.persistence
        let url = await Task.detached(priority: .userInitiated) {
            persistence.saveWebURL(webURL, title: title)
        }.value
        guard let url else { return nil }
        let ids = await add(urls: [url])
        return ids.first
    }

    func addText(_ text: String) async -> UUID? {
        let persistence = self.persistence
        let url = await Task.detached(priority: .userInitiated) {
            persistence.saveText(text)
        }.value
        guard let url else { return nil }
        let ids = await add(urls: [url])
        return ids.first
    }

    func zipItems(_ targetItems: [ShelfItem]) async -> UUID? {
        let urls = targetItems.compactMap { $0.isMissing ? nil : $0.resolvedURL }
        guard !urls.isEmpty, !isZipping else { return nil }
        isZipping = true
        defer { isZipping = false }
        let persistence = self.persistence
        let zipURL = await Task.detached(priority: .userInitiated) {
            persistence.createZip(from: urls)
        }.value
        guard let zipURL else { return nil }
        let ids = await add(urls: [zipURL])
        return ids.first
    }

    @discardableResult
    func remove(id: UUID) -> [URL] {
        remove(ids: [id])
    }

    @discardableResult
    func remove(ids: [UUID]) -> [URL] {
        let idSet = Set(ids)
        let toRemove = items.filter { idSet.contains($0.id) }
        guard !toRemove.isEmpty else { return [] }
        var restored: [URL] = []
        for item in toRemove {
            if let url = persistence.restoreOrDelete(item) {
                restored.append(url)
            }
        }
        items.removeAll { idSet.contains($0.id) }
        selectedIDs.subtract(idSet)
        if let last = lastSelectedID, idSet.contains(last) {
            lastSelectedID = nil
        }
        save()
        return restored
    }

    @discardableResult
    func clear() -> [URL] {
        var restored: [URL] = []
        for item in items {
            if let url = persistence.restoreOrDelete(item) {
                restored.append(url)
            }
        }
        items = []
        selectedIDs = []
        lastSelectedID = nil
        save()
        return restored
    }

    func select(_ item: ShelfItem, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selectedIDs.contains(item.id) {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
                lastSelectedID = item.id
            }
        } else if modifiers.contains(.shift),
                  let anchor = lastSelectedID,
                  let anchorIdx = items.firstIndex(where: { $0.id == anchor }),
                  let targetIdx = items.firstIndex(where: { $0.id == item.id }) {
            let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
            selectedIDs.formUnion(items[range].map(\.id))
        } else {
            selectedIDs = [item.id]
            lastSelectedID = item.id
        }
    }

    func selectAll() {
        selectedIDs = Set(items.map(\.id))
    }

    func clearSelection() {
        selectedIDs = []
        lastSelectedID = nil
    }

    func itemsForAction(targeting item: ShelfItem) -> [ShelfItem] {
        if selectedIDs.contains(item.id), selectedIDs.count > 1 {
            return items.filter { selectedIDs.contains($0.id) }
        }
        return [item]
    }

    func dragEntries(startingFrom item: ShelfItem) -> [(id: UUID, url: URL)] {
        let targets = itemsForAction(targeting: item)
        return targets.compactMap { candidate in
            guard let url = candidate.resolvedURL, !candidate.isMissing else { return nil }
            return (candidate.id, url)
        }
    }

    func handleDragCompleted(ids: [UUID], operation: NSDragOperation) {
        guard !operation.isEmpty else { return }
        let idSet = Set(ids)
        let dragged = items.filter { idSet.contains($0.id) }
        guard !dragged.isEmpty else { return }

        var movedAwayIDs: Set<UUID> = []
        var copiedOnlyIDs: [UUID] = []

        for item in dragged {
            let fileGone = item.resolvedURL.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false
            if operation.contains(.move) || fileGone {
                persistence.cleanupEmptyContainer(relativePath: item.storedCopyRelativePath)
                movedAwayIDs.insert(item.id)
            } else {
                copiedOnlyIDs.append(item.id)
            }
        }

        if !movedAwayIDs.isEmpty {
            items.removeAll { movedAwayIDs.contains($0.id) }
            selectedIDs.subtract(movedAwayIDs)
            if let last = lastSelectedID, movedAwayIDs.contains(last) {
                lastSelectedID = nil
            }
            save()
        }

        if removeAfterDrag, !copiedOnlyIDs.isEmpty {
            remove(ids: copiedOnlyIDs)
        }
    }

    func copyFiles(_ targetItems: [ShelfItem]) {
        let urls = targetItems.compactMap { $0.isMissing ? nil : $0.resolvedURL as NSURL? }
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls)
    }

    func copyPaths(_ targetItems: [ShelfItem]) {
        let paths = targetItems.compactMap { $0.isMissing ? nil : $0.resolvedURL?.path }
        guard !paths.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paths.joined(separator: "\n"), forType: .string)
    }

    func quickLook(_ targetItems: [ShelfItem]) {
        let urls = targetItems.compactMap { $0.isMissing ? nil : $0.resolvedURL }
        guard !urls.isEmpty else { return }
        QuickLookController.shared.toggle(urls: urls)
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

    static func webURL(from pasteboard: NSPasteboard) -> (url: URL, title: String?)? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first(where: { !$0.isFileURL && ($0.scheme == "http" || $0.scheme == "https") }) {
            let titleType = NSPasteboard.PasteboardType("public.url-name")
            let title = pasteboard.string(forType: titleType)
            return (url, title)
        }
        if let str = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !str.contains(where: \.isWhitespace),
           let url = URL(string: str),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host != nil {
            return (url, nil)
        }
        return nil
    }

    static func text(from pasteboard: NSPasteboard) -> String? {
        guard let str = pasteboard.string(forType: .string) else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : str
    }

    static func hasFileDrag(_ pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types, !types.isEmpty else { return false }
        if types.contains(.fileURL) { return true }
        if types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) { return true }
        if types.contains(.png) || types.contains(.tiff) { return true }
        if types.contains(NSPasteboard.PasteboardType(UTType.jpeg.identifier)) { return true }
        if types.contains(.URL) || types.contains(.string) { return true }
        let promises = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        return types.contains { promises.contains($0) }
    }
}
