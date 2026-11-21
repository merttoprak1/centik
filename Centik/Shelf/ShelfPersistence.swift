import Foundation
import os

/// Stores bookmarks to the original files. Temporary drag sources are copied
/// into Application Support so they survive after the source deletes them.
struct ShelfPersistence {
    private let log = Logger(subsystem: "app.centik.Centik", category: "shelf")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Centik", isDirectory: true)
    }

    private var filesDirectory: URL {
        supportDirectory.appendingPathComponent("Files", isDirectory: true)
    }

    private var indexURL: URL {
        supportDirectory.appendingPathComponent("shelf.json")
    }

    func load() -> [ShelfItem] {
        guard let data = try? Data(contentsOf: indexURL),
              let file = try? decoder.decode(PersistedShelf.self, from: data) else {
            return []
        }
        return file.items.map { restore($0) }
    }

    func save(_ items: [ShelfItem]) {
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            let file = PersistedShelf(version: 1, items: items.map(persist))
            let data = try encoder.encode(file)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            log.error("Could not save the shelf: \(error.localizedDescription, privacy: .public)")
        }
    }

    func importFile(at url: URL) -> ShelfItem {
        let id = UUID()
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .localizedNameKey])
        let isDirectory = values?.isDirectory ?? false
        let displayName = values?.localizedName ?? url.lastPathComponent
        let standardized = url.standardizedFileURL

        if let relative = relativeStoredPath(for: standardized) {
            let bookmark = makeBookmark(for: standardized) ?? Data()
            return ShelfItem(
                id: id,
                displayName: displayName,
                resolvedURL: standardized,
                isDirectory: isDirectory,
                isMissing: false,
                storedCopyRelativePath: relative,
                bookmarkData: bookmark,
                pathFallback: standardized.path,
                addedAt: Date()
            )
        }

        if Self.isEphemeral(standardized), let copy = copyIntoStorage(standardized, id: id) {
            let relative = relativeStoredPath(for: copy)
            let bookmark = makeBookmark(for: copy) ?? Data()
            let copyValues = try? copy.resourceValues(forKeys: [.localizedNameKey])
            return ShelfItem(
                id: id,
                displayName: copyValues?.localizedName ?? displayName,
                resolvedURL: copy,
                isDirectory: isDirectory,
                isMissing: false,
                storedCopyRelativePath: relative,
                bookmarkData: bookmark,
                pathFallback: copy.path,
                addedAt: Date()
            )
        }

        let bookmark = makeBookmark(for: standardized) ?? Data()
        return ShelfItem(
            id: id,
            displayName: displayName,
            resolvedURL: standardized,
            isDirectory: isDirectory,
            isMissing: !exists(standardized),
            storedCopyRelativePath: nil,
            bookmarkData: bookmark,
            pathFallback: standardized.path,
            addedAt: Date()
        )
    }

    func saveImageData(_ data: Data, fileExtension: String) -> URL? {
        let id = UUID()
        let directory = filesDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("Image").appendingPathExtension(fileExtension)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            log.error("Could not store dropped image: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func deleteStoredCopy(relativePath: String?) {
        guard let relativePath, !relativePath.isEmpty else { return }
        let file = filesDirectory.appendingPathComponent(relativePath)
        let directory = file.deletingLastPathComponent()
        guard directory.path.hasPrefix(filesDirectory.path), directory.path != filesDirectory.path else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    func refresh(_ item: ShelfItem) -> ShelfItem {
        var item = item
        if let resolved = resolve(item.bookmarkData) {
            item.resolvedURL = resolved.url
            item.pathFallback = resolved.url.path
            if resolved.stale, let refreshed = makeBookmark(for: resolved.url) {
                item.bookmarkData = refreshed
            }
            if let name = try? resolved.url.resourceValues(forKeys: [.localizedNameKey]).localizedName {
                item.displayName = name
            }
            item.isMissing = !exists(resolved.url)
            if item.isMissing, let relative = item.storedCopyRelativePath {
                let copy = filesDirectory.appendingPathComponent(relative)
                if exists(copy) {
                    item.resolvedURL = copy
                    item.isMissing = false
                    item.pathFallback = copy.path
                }
            }
            return item
        }

        if let relative = item.storedCopyRelativePath {
            let copy = filesDirectory.appendingPathComponent(relative)
            if exists(copy) {
                item.resolvedURL = copy
                item.isMissing = false
                item.pathFallback = copy.path
                if item.bookmarkData.isEmpty, let bookmark = makeBookmark(for: copy) {
                    item.bookmarkData = bookmark
                }
                return item
            }
        }

        if let path = item.pathFallback {
            let url = URL(fileURLWithPath: path)
            if exists(url) {
                item.resolvedURL = url
                item.isMissing = false
                if item.bookmarkData.isEmpty, let bookmark = makeBookmark(for: url) {
                    item.bookmarkData = bookmark
                }
                return item
            }
        }

        item.resolvedURL = nil
        item.isMissing = true
        return item
    }

    private func restore(_ stored: PersistedShelfItem) -> ShelfItem {
        refresh(ShelfItem(
            id: stored.id,
            displayName: stored.displayName,
            resolvedURL: nil,
            isDirectory: stored.isDirectory,
            isMissing: true,
            storedCopyRelativePath: stored.storedCopyRelativePath,
            bookmarkData: stored.bookmark,
            pathFallback: stored.pathFallback,
            addedAt: stored.addedAt
        ))
    }

    private func persist(_ item: ShelfItem) -> PersistedShelfItem {
        PersistedShelfItem(
            id: item.id,
            displayName: item.displayName,
            bookmark: item.bookmarkData,
            pathFallback: item.pathFallback,
            storedCopyRelativePath: item.storedCopyRelativePath,
            isDirectory: item.isDirectory,
            addedAt: item.addedAt
        )
    }

    private func makeBookmark(for url: URL) -> Data? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            return data
        }
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func resolve(_ data: Data) -> (url: URL, stale: Bool)? {
        guard !data.isEmpty else { return nil }
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            return (url, stale)
        }
        stale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            return (url, stale)
        }
        return nil
    }

    private func exists(_ url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func copyIntoStorage(_ url: URL, id: UUID) -> URL? {
        let directory = filesDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            log.error("Could not keep a temporary drop: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func relativeStoredPath(for url: URL) -> String? {
        let base = filesDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base + "/") else { return nil }
        return String(path.dropFirst(base.count + 1))
    }

    /// Drags from other apps often land in a temporary folder that disappears
    /// when the drag ends. Those need a real copy. Everything else is bookmarked.
    static func isEphemeral(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        if path.hasPrefix(temporary) { return true }
        let inVarFolders = path.contains("/var/folders/")
        guard inVarFolders else { return false }
        let markers = ["/TemporaryItems/", "/T/", "/NSIRD_"]
        return markers.contains { path.contains($0) }
    }
}
