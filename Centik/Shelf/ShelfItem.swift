import Foundation

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    var displayName: String
    var resolvedURL: URL?
    var isDirectory: Bool
    var isMissing: Bool
    var storedCopyRelativePath: String?
    var bookmarkData: Data
    var pathFallback: String?
    var addedAt: Date

    var tooltip: String {
        if isMissing {
            return "\(displayName) — original file is missing"
        }
        return resolvedURL?.path ?? displayName
    }
}

struct PersistedShelf: Codable {
    var version: Int
    var items: [PersistedShelfItem]
}

struct PersistedShelfItem: Codable {
    var id: UUID
    var displayName: String
    var bookmark: Data
    var pathFallback: String?
    var storedCopyRelativePath: String?
    var isDirectory: Bool
    var addedAt: Date
}
