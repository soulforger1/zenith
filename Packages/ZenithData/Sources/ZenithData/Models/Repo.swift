import Foundation

/// Port of the `repos` table — a GitHub repo linked to a space.
/// `cachedContext` is an AI-generated summary refreshed only by an explicit
/// manual "Sync" — repo content is never fetched live on every task-parse.
public struct Repo: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let spaceId: UUID
    public var name: String
    public var url: String
    public var cachedContext: String?
    public var cachedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID, spaceId: UUID, name: String, url: String, cachedContext: String?,
        cachedAt: Date?, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.spaceId = spaceId
        self.name = name
        self.url = url
        self.cachedContext = cachedContext
        self.cachedAt = cachedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
