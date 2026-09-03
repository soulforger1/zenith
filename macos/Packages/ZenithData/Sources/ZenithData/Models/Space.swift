import Foundation

/// Port of the `spaces` table (`lib/db/schema.ts`).
public struct Space: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var slug: String
    public var description: String?
    /// Free text prepended to every AI paste-task prompt for this space.
    public var context: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID, name: String, slug: String, description: String?, context: String?,
        createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.description = description
        self.context = context
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
