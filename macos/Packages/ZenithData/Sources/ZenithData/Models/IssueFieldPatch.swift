import Foundation

/// Port of `IssueFieldPatch` (`lib/db/queries/issues.ts`) — generic per-field
/// autosave patch used by the task detail drawer and the Kanban board's
/// drag-drop. Nullable columns use `T??` deliberately: the outer `nil`
/// means "not part of this patch, leave the column alone" (matches the TS
/// side's `Partial<>`), while `.some(nil)` means "explicitly clear this
/// column to NULL" (matches the TS side's `.nullable()`). Non-nullable
/// columns (title, status, priority, tags, repoIds, position) only need a
/// single-level `T?` since they can never be explicitly cleared.
public struct IssueFieldPatch: Sendable {
    public var title: String?
    public var description: String??
    public var status: IssueStatus?
    public var priority: IssuePriority?
    public var tags: [String]?
    public var branch: String??
    public var estimate: String??
    public var parentId: UUID??
    public var milestoneId: UUID??
    public var repoIds: [UUID]?
    public var dueDate: String??
    public var startDate: String??
    /// Only ever set together with a group-field patch, from the Kanban
    /// board's drag-drop (any grouping, not just status).
    public var position: Double?
    /// A *partial* map of custom field id -> value — merged into the
    /// existing `customFieldValues` jsonb (not a full overwrite).
    public var customFieldValues: [String: AnyCodableValue]?

    public init(
        title: String? = nil,
        description: String?? = nil,
        status: IssueStatus? = nil,
        priority: IssuePriority? = nil,
        tags: [String]? = nil,
        branch: String?? = nil,
        estimate: String?? = nil,
        parentId: UUID?? = nil,
        milestoneId: UUID?? = nil,
        repoIds: [UUID]? = nil,
        dueDate: String?? = nil,
        startDate: String?? = nil,
        position: Double? = nil,
        customFieldValues: [String: AnyCodableValue]? = nil
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.tags = tags
        self.branch = branch
        self.estimate = estimate
        self.parentId = parentId
        self.milestoneId = milestoneId
        self.repoIds = repoIds
        self.dueDate = dueDate
        self.startDate = startDate
        self.position = position
        self.customFieldValues = customFieldValues
    }
}
