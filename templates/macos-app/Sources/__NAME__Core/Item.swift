import Foundation

public struct Item: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var isDone: Bool
    public let createdAt: Date

    public init(id: UUID = UUID(), title: String, isDone: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
    }

    /// The first eight characters of the id, which the CLI accepts as an id prefix.
    public var shortID: String {
        String(id.uuidString.prefix(8)).lowercased()
    }
}
