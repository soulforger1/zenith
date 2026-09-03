import Foundation

/// Port of `lib/issue-types.ts` — the subset of an issue's fields the UI
/// (list rows, kanban cards, the task detail drawer) actually needs.
/// `repoIds`/`subtaskCount` aren't columns on `issues` (many-to-many via
/// `issue_repos`, and derived from child rows respectively) — callers fetch
/// them separately (`IssueQueries.repoIds(forIssueIds:)`,
/// `IssueQueries.subtaskCounts(forParentIds:)`) and pass them in here.
public struct SubtaskCount: Sendable, Equatable {
    public var total: Int
    public var done: Int

    public init(total: Int, done: Int) {
        self.total = total
        self.done = done
    }

    public static let zero = SubtaskCount(total: 0, done: 0)
}

public struct IssueRecord: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var description: String?
    public var status: IssueStatus
    public var priority: IssuePriority
    public var tags: [String]
    public var branch: String?
    public var estimate: String?
    public var parentId: UUID?
    public var subtaskCount: SubtaskCount
    public var dueDate: String?
    public var startDate: String?
    public var milestoneId: UUID?
    public var repoIds: [UUID]
    public var customFieldValues: [String: AnyCodableValue]
    /// Not part of the TS `IssueRecord` (only its `KanbanIssue = DrawerTask
    /// & { position: number }` extension carries this) — included here
    /// directly since Swift's static typing makes a separate
    /// board-specific record type more friction than it's worth for one
    /// extra field, and the Table view is free to just ignore it.
    public var position: Double

    public init(
        id: UUID, title: String, description: String?, status: IssueStatus, priority: IssuePriority,
        tags: [String], branch: String?, estimate: String?, parentId: UUID?, subtaskCount: SubtaskCount,
        dueDate: String?, startDate: String?, milestoneId: UUID?, repoIds: [UUID],
        customFieldValues: [String: AnyCodableValue], position: Double
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.tags = tags
        self.branch = branch
        self.estimate = estimate
        self.parentId = parentId
        self.subtaskCount = subtaskCount
        self.dueDate = dueDate
        self.startDate = startDate
        self.milestoneId = milestoneId
        self.repoIds = repoIds
        self.customFieldValues = customFieldValues
        self.position = position
    }
}

extension Issue {
    public func toRecord(repoIds: [UUID] = [], subtaskCount: SubtaskCount = .zero) -> IssueRecord {
        IssueRecord(
            id: id,
            title: title,
            description: description,
            status: status,
            priority: priority,
            tags: tags,
            branch: branch,
            estimate: estimate,
            parentId: parentId,
            subtaskCount: subtaskCount,
            dueDate: dueDate,
            startDate: startDate,
            milestoneId: milestoneId,
            repoIds: repoIds,
            customFieldValues: customFieldValues,
            position: position
        )
    }
}

extension Array where Element == Issue {
    public func toRecords(
        repoIdsByIssue: [UUID: [UUID]] = [:],
        subtaskCountByIssue: [UUID: SubtaskCount] = [:]
    ) -> [IssueRecord] {
        map { $0.toRecord(repoIds: repoIdsByIssue[$0.id] ?? [], subtaskCount: subtaskCountByIssue[$0.id] ?? .zero) }
    }
}
