import Foundation
import os

/// Stores bookmarks to the original files. Temporary drag sources are copied
/// into Application Support so they survive after the source deletes them.
struct ShelfPersistence: Sendable {
    private let log = Logger(subsystem: "app.centik.Centik", category: "shelf")

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

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
              let file = try? makeDecoder().decode(PersistedShelf.self, from: data) else {
            return []
        }
        return file.items.map { restore($0) }
    }

    func save(_ items: [ShelfItem]) {
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            let file = PersistedShelf(version: 1, items: items.map(persist))
            let data = try makeEncoder().encode(file)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            log.error("Could not save the shelf: \(error.localizedDescription, privacy: .public)")
        }
    }

    func importFile(at url: URL, moveToShelf: Bool = true) -> ShelfItem {
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
                movedFromPath: nil,
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
                movedFromPath: nil,
                bookmarkData: bookmark,
                pathFallback: copy.path,
                addedAt: Date()
            )
        }

        if moveToShelf, let moved = moveIntoStorage(standardized, id: id) {
            let relative = relativeStoredPath(for: moved)
            let bookmark = makeBookmark(for: moved) ?? Data()
            let movedValues = try? moved.resourceValues(forKeys: [.localizedNameKey])
            return ShelfItem(
                id: id,
                displayName: movedValues?.localizedName ?? displayName,
                resolvedURL: moved,
                isDirectory: isDirectory,
                isMissing: false,
                storedCopyRelativePath: relative,
                movedFromPath: standardized.path,
                bookmarkData: bookmark,
                pathFallback: moved.path,
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
            movedFromPath: nil,
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

    func saveWebURL(_ webURL: URL, title: String?) -> URL? {
        let id = UUID()
        let directory = filesDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let rawName = (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title! : nil)
            ?? webURL.host
            ?? "Link"
        let baseName = Self.sanitizedFilename(rawName, fallback: "Link")
        let url = directory.appendingPathComponent(baseName).appendingPathExtension("webloc")
        let plist: [String: Any] = ["URL": webURL.absoluteString]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            log.error("Could not store dropped URL: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func saveText(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let id = UUID()
        let directory = filesDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? "Snippet"
        let baseName = Self.sanitizedFilename(firstLine, fallback: "Snippet")
        let url = directory.appendingPathComponent(baseName).appendingPathExtension("txt")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            log.error("Could not store dropped text: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func createZip(from urls: [URL], archiveName: String? = nil) -> URL? {
        guard !urls.isEmpty else { return nil }
        let id = UUID()
        let directory = filesDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("CentikZip-\(id.uuidString)", isDirectory: true)

        let baseName: String
        if let archiveName, !archiveName.isEmpty {
            baseName = Self.sanitizedFilename(archiveName, fallback: "Archive")
        } else if urls.count == 1 {
            baseName = Self.sanitizedFilename(urls[0].deletingPathExtension().lastPathComponent, fallback: "Archive")
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            baseName = "Shelf-\(formatter.string(from: Date()))"
        }
        let zipURL = directory.appendingPathComponent(baseName).appendingPathExtension("zip")

        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sourceToZip: URL
            let keepParent: Bool
            if urls.count == 1 {
                sourceToZip = urls[0]
                keepParent = true
            } else {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                for url in urls {
                    let target = uniqueDestination(in: staging, filename: url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: target)
                }
                sourceToZip = staging
                keepParent = false
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            var args = ["-c", "-k", "--sequesterRsrc"]
            if keepParent { args.append("--keepParent") }
            args.append(contentsOf: [sourceToZip.path, zipURL.path])
            process.arguments = args
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: zipURL.path) else {
                try? FileManager.default.removeItem(at: directory)
                return nil
            }
            return zipURL
        } catch {
            log.error("Could not create zip archive: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
    }

    private func uniqueDestination(in directory: URL, filename: String) -> URL {
        var candidate = directory.appendingPathComponent(filename)
        var counter = 2
        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            candidate = directory.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }

    private static func sanitizedFilename(_ raw: String, fallback: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = raw
            .components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(cleaned.prefix(48)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return prefix.isEmpty ? fallback : prefix
    }

    /// Restores a moved file back to its original folder, or deletes a temporary/generated copy.
    /// Returns the restored destination URL when a moved file was returned.
    @discardableResult
    func restoreOrDelete(_ item: ShelfItem) -> URL? {
        if let movedFromPath = item.movedFromPath,
           let relativePath = item.storedCopyRelativePath {
            let storedURL = filesDirectory.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: storedURL.path) else {
                cleanupEmptyContainer(relativePath: relativePath)
                return nil
            }
            let originalURL = URL(fileURLWithPath: movedFromPath)
            let parentDir: URL
            if FileManager.default.fileExists(atPath: originalURL.deletingLastPathComponent().path) {
                parentDir = originalURL.deletingLastPathComponent()
            } else {
                parentDir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop", isDirectory: true)
            }
            let destination = uniqueDestination(in: parentDir, filename: originalURL.lastPathComponent)
            do {
                try FileManager.default.moveItem(at: storedURL, to: destination)
                cleanupEmptyContainer(relativePath: relativePath)
                return destination
            } catch {
                log.error("Could not restore shelved file to \(destination.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        deleteStoredCopy(relativePath: item.storedCopyRelativePath)
        return nil
    }

    func cleanupEmptyContainer(relativePath: String?) {
        guard let relativePath, !relativePath.isEmpty else { return }
        let file = filesDirectory.appendingPathComponent(relativePath)
        let directory = file.deletingLastPathComponent()
        guard directory.path.hasPrefix(filesDirectory.path), directory.path != filesDirectory.path else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        if contents.isEmpty {
            try? FileManager.default.removeItem(at: directory)
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
            movedFromPath: stored.movedFromPath,
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
            movedFromPath: item.movedFromPath,
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

    private func moveIntoStorage(_ url: URL, id: UUID) -> URL? {
        let directory = filesDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: directory)
            log.info("Falling back to bookmark for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
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
