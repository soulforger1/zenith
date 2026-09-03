import Foundation

/// Port of the `milestones` table. Progress is always computed on read from
/// linked issues (see `IssueQueries.milestoneProgress`) — never stored.
public struct Milestone: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let spaceId: UUID
    public var title: String
    public var description: String?
    /// ISO `YYYY-MM-DD`, stored as Postgres `date` (no time-of-day).
    public var dueDate: String?
    public var status: String
    public var closedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date

    public var isClosed: Bool { status == "closed" }

    public init(
        id: UUID, spaceId: UUID, title: String, description: String?, dueDate: String?,
        status: String, closedAt: Date?, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.spaceId = spaceId
        self.title = title
        self.description = description
        self.dueDate = dueDate
        self.status = status
        self.closedAt = closedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
