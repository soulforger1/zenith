import Foundation

/// Port of the `issues` table — the actual to-dos. `status` drives both the
/// Kanban columns and "done"-ness; `isClosed`/`closedAt` are kept in sync
/// automatically whenever status flips to/from `done` (see `IssueActions`),
/// but nothing else in the app treats them as an independent concept.
/// Subtasks are just issues whose `parentId` points at another issue
/// (self-referential, GitHub-sub-issues-style).
public struct Issue: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let spaceId: UUID
    public var milestoneId: UUID?
    public var parentId: UUID?
    public var title: String
    public var description: String?
    public var status: IssueStatus
    public var isClosed: Bool
    public var priority: IssuePriority
    public var tags: [String]
    public var branch: String?
    public var estimate: String?
    /// ISO `YYYY-MM-DD`, stored as Postgres `date`.
    public var dueDate: String?
    public var startDate: String?
    /// Keyed by `custom_fields.id`; value shape depends on the field's
    /// `type` (string/number/option-id/option-id-array/iteration-id).
    public var customFieldValues: [String: AnyCodableValue]
    public var position: Double
    public var closedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID, spaceId: UUID, milestoneId: UUID?, parentId: UUID?, title: String,
        description: String?, status: IssueStatus, isClosed: Bool, priority: IssuePriority,
        tags: [String], branch: String?, estimate: String?, dueDate: String?, startDate: String?,
        customFieldValues: [String: AnyCodableValue], position: Double, closedAt: Date?,
        createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.spaceId = spaceId
        self.milestoneId = milestoneId
        self.parentId = parentId
        self.title = title
        self.description = description
        self.status = status
        self.isClosed = isClosed
        self.priority = priority
        self.tags = tags
        self.branch = branch
        self.estimate = estimate
        self.dueDate = dueDate
        self.startDate = startDate
        self.customFieldValues = customFieldValues
        self.position = position
        self.closedAt = closedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
