import Foundation

public enum ItemStoreError: Error, Equatable, LocalizedError {
    case emptyTitle
    case notFound(UUID)
    case noMatch(String)
    case ambiguous(String, count: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "제목이 비어 있습니다."
        case .notFound(let id):
            "항목이 없습니다: \(id.uuidString.lowercased())"
        case .noMatch(let prefix):
            "id 가 '\(prefix)' 로 시작하는 항목이 없습니다."
        case .ambiguous(let prefix, let count):
            "id 가 '\(prefix)' 로 시작하는 항목이 \(count)개입니다. 더 길게 적으세요."
        }
    }
}

/// Keeps items in `items.json` inside a directory. Every call reads the file again,
/// so changes made by another process (the CLI or the app) are always visible.
public struct ItemStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appending(path: "items.json")
    }

    public func list() throws -> [Item] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Item].self, from: Data(contentsOf: fileURL))
    }

    @discardableResult
    public func add(title: String) throws -> Item {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw ItemStoreError.emptyTitle
        }
        // Whole seconds, so the date survives the ISO 8601 round trip unchanged.
        let now = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down))
        let item = Item(title: title, createdAt: now)
        try save(list() + [item])
        return item
    }

    public func setDone(id: UUID, _ isDone: Bool) throws {
        var items = try list()
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw ItemStoreError.notFound(id)
        }
        items[index].isDone = isDone
        try save(items)
    }

    public func remove(id: UUID) throws {
        var items = try list()
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw ItemStoreError.notFound(id)
        }
        items.remove(at: index)
        try save(items)
    }

    /// The single item whose id starts with `prefix`, ignoring case.
    public func item(matchingIDPrefix prefix: String) throws -> Item {
        let needle = prefix.lowercased()
        let matches = try list().filter { !needle.isEmpty && $0.id.uuidString.lowercased().hasPrefix(needle) }
        guard matches.count <= 1 else {
            throw ItemStoreError.ambiguous(prefix, count: matches.count)
        }
        guard let item = matches.first else {
            throw ItemStoreError.noMatch(prefix)
        }
        return item
    }

    /// The JSON used both for `items.json` and for `list --json`.
    public static func encode(_ items: [Item]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(items)
    }

    private func save(_ items: [Item]) throws {
        try Self.encode(items).write(to: fileURL, options: .atomic)
    }
}
