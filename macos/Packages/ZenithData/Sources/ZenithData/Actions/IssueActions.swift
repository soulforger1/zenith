import Foundation

/// Port of `lib/actions/issues.ts` — the largest/highest-risk business-logic
/// file in the app (bulk ops, drag-drop position math, subtask handling).
/// `revalidatePath` has no native equivalent — callers refresh their own
/// view-model state from the returned value on success.
public enum IssueActions {
    // MARK: - Validation (mirrors `draftSchema`/`fieldPatchSchema`)

    private static func validateTitle(_ title: String, max: Int = 200) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError(field: "title", message: "Title is required.") }
        guard trimmed.count <= max else { throw ValidationError(field: "title", message: "Title is too long.") }
        return trimmed
    }

    private static func validateTags(_ tags: [String]) throws -> [String] {
        guard tags.count <= 8 else { throw ValidationError(field: "tags", message: "At most 8 tags allowed.") }
        return try tags.map { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 30 else {
                throw ValidationError(field: "tags", message: "Each tag must be 1-30 characters.")
            }
            return trimmed
        }
    }

    private static func validateOptional(_ value: String?, field: String, max: Int) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= max else { throw ValidationError(field: field, message: "\(field) is too long.") }
        return trimmed
    }

    /// One task draft, as fed by the AI paste-task/paste-list flows or a
    /// manual "new task" form — mirrors `draftSchema`.
    public struct TaskDraft: Sendable {
        public var title: String
        public var description: String?
        public var priority: IssuePriority
        public var tags: [String]
        public var branch: String?
        public var estimate: String?
        public var dueDate: String?
        public var startDate: String?
        public var repoIds: [UUID]
        public var milestoneId: UUID?
        public var customFieldValues: [String: AnyCodableValue]

        public init(
            title: String, description: String? = nil, priority: IssuePriority = .medium, tags: [String] = [],
            branch: String? = nil, estimate: String? = nil, dueDate: String? = nil, startDate: String? = nil,
            repoIds: [UUID] = [], milestoneId: UUID? = nil, customFieldValues: [String: AnyCodableValue] = [:]
        ) {
            self.title = title
            self.description = description
            self.priority = priority
            self.tags = tags
            self.branch = branch
            self.estimate = estimate
            self.dueDate = dueDate
            self.startDate = startDate
            self.repoIds = repoIds
            self.milestoneId = milestoneId
            self.customFieldValues = customFieldValues
        }

        func validated() throws -> IssueQueries.NewIssueInput {
            guard repoIds.count <= 20 else { throw ValidationError(field: "repoIds", message: "At most 20 repos allowed.") }
            return IssueQueries.NewIssueInput(
                spaceId: UUID(), // overwritten by the caller
                title: try validateTitle(title),
                description: try validateOptional(description, field: "description", max: 2000),
                priority: priority,
                tags: try validateTags(tags),
                branch: try validateOptional(branch, field: "branch", max: 100),
                estimate: try validateOptional(estimate, field: "estimate", max: 20),
                dueDate: dueDate,
                startDate: startDate,
                customFieldValues: customFieldValues
            )
        }
    }

    // MARK: - Create

    /// Quick-add: create a task with just a title in a given column.
    public static func createIssue(_ db: ZenithDatabase, spaceId: UUID, status: IssueStatus, title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try await IssueQueries.createIssue(db, .init(spaceId: spaceId, title: trimmed, status: status))
    }

    /// Full task creation (used by the AI paste-and-parse modal).
    public static func createIssueFromDraft(_ db: ZenithDatabase, spaceId: UUID, draft: TaskDraft) async throws {
        var input = try draft.validated()
        input.spaceId = spaceId
        input.status = .backlog
        input.repoIds = draft.repoIds
        input.milestoneId = draft.milestoneId
        _ = try await IssueQueries.createIssue(db, input)
    }

    /// Bulk task creation (used by the AI paste-a-list modal).
    public static func createIssuesFromDrafts(_ db: ZenithDatabase, spaceId: UUID, drafts: [TaskDraft]) async throws {
        guard !drafts.isEmpty else { throw ValidationError(field: "drafts", message: "At least one task is required.") }
        guard drafts.count <= 50 else { throw ValidationError(field: "drafts", message: "At most 50 tasks at once.") }
        var inputs: [IssueQueries.NewIssueInput] = []
        for draft in drafts {
            var input = try draft.validated()
            input.spaceId = spaceId
            input.repoIds = draft.repoIds
            input.milestoneId = draft.milestoneId
            inputs.append(input)
        }
        _ = try await IssueQueries.createIssues(db, spaceId: spaceId, drafts: inputs)
    }

    // MARK: - Update

    /// Validates a raw patch's present fields, mirroring `fieldPatchSchema`.
    private static func validatePatch(_ patch: IssueFieldPatch) throws -> IssueFieldPatch {
        var validated = patch
        if let title = patch.title { validated.title = try validateTitle(title) }
        if let tags = patch.tags { validated.tags = try validateTags(tags) }
        if let repoIds = patch.repoIds {
            guard repoIds.count <= 20 else { throw ValidationError(field: "repoIds", message: "At most 20 repos allowed.") }
        }

        // Each of these three is `T??`: `.some(nil)` means "explicitly clear
        // this column", so each branch must preserve that distinction
        // rather than collapsing it back to a plain `nil` (which would mean
        // "not part of this patch" instead).
        if case .some(let description) = patch.description {
            if let description {
                let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count <= 5000 else { throw ValidationError(field: "description", message: "Description is too long.") }
                validated.description = .some(trimmed)
            } else {
                validated.description = .some(nil)
            }
        }
        if case .some(let branch) = patch.branch {
            if let branch {
                let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count <= 100 else { throw ValidationError(field: "branch", message: "Branch is too long.") }
                validated.branch = .some(trimmed)
            } else {
                validated.branch = .some(nil)
            }
        }
        if case .some(let estimate) = patch.estimate {
            if let estimate {
                let trimmed = estimate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count <= 20 else { throw ValidationError(field: "estimate", message: "Estimate is too long.") }
                validated.estimate = .some(trimmed)
            } else {
                validated.estimate = .some(nil)
            }
        }
        return validated
    }

    /// Per-field autosave from the task detail drawer — pass only what changed.
    public static func updateIssueFields(_ db: ZenithDatabase, id: UUID, patch: IssueFieldPatch) async throws -> Issue? {
        try await IssueQueries.updateIssueFields(db, id: id, patch: try validatePatch(patch))
    }

    public static func deleteIssue(_ db: ZenithDatabase, id: UUID) async throws {
        try await IssueQueries.deleteIssue(db, id: id)
    }

    /// Called from the Kanban board's onDragEnd — `patch` is whatever field
    /// the board is currently grouped by (status, priority, milestoneId,
    /// repoIds, or a customFieldValues entry), always paired with the
    /// dragged card's new fractional position.
    public static func updateIssueGroup(_ db: ZenithDatabase, id: UUID, patch: IssueFieldPatch, position: Double) async throws -> Issue? {
        var combined = patch
        combined.position = position
        return try await updateIssueFields(db, id: id, patch: combined)
    }

    // MARK: - Bulk actions (selection toolbar)

    public static func bulkUpdateStatus(_ db: ZenithDatabase, ids: [UUID], status: IssueStatus) async throws {
        try await IssueQueries.bulkUpdateStatus(db, ids: ids, status: status)
    }

    public static func bulkUpdatePriority(_ db: ZenithDatabase, ids: [UUID], priority: IssuePriority) async throws {
        try await IssueQueries.bulkUpdatePriority(db, ids: ids, priority: priority)
    }

    public static func bulkDeleteIssues(_ db: ZenithDatabase, ids: [UUID]) async throws {
        try await IssueQueries.bulkDeleteIssues(db, ids: ids)
    }

    // MARK: - Reads used by the task detail drawer

    /// Builds a full IssueRecord for one issue — used wherever the drawer
    /// needs a task it wasn't handed as a prop (a parent breadcrumb, a
    /// freshly-created or freshly-linked child).
    public static func getIssueRecord(_ db: ZenithDatabase, id: UUID) async throws -> IssueRecord? {
        guard let issue = try await IssueQueries.getIssueById(db, id: id) else { return nil }
        async let repoIdsMap = IssueQueries.repoIds(db, forIssueIds: [id])
        async let subtaskCountMap = IssueQueries.subtaskCounts(db, forParentIds: [id])
        let (repos, counts) = try await (repoIdsMap, subtaskCountMap)
        return issue.toRecord(repoIds: repos[id] ?? [], subtaskCount: counts[id] ?? .zero)
    }

    public static func getChildIssues(_ db: ZenithDatabase, parentId: UUID) async throws -> [IssueRecord] {
        let children = try await IssueQueries.getChildIssues(db, parentId: parentId)
        let ids = children.map(\.id)
        async let repoIdsMap = IssueQueries.repoIds(db, forIssueIds: ids)
        async let subtaskCountMap = IssueQueries.subtaskCounts(db, forParentIds: ids)
        let (repos, counts) = try await (repoIdsMap, subtaskCountMap)
        return children.toRecords(repoIdsByIssue: repos, subtaskCountByIssue: counts)
    }

    /// Quick-add a subtask from the drawer — looks up the parent to inherit
    /// its `spaceId` so the drawer doesn't need to carry that around
    /// separately.
    public static func createSubtask(_ db: ZenithDatabase, parentId: UUID, title: String) async throws -> IssueRecord? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parent = try await IssueQueries.getIssueById(db, id: parentId) else {
            throw ValidationError(field: "parentId", message: "Parent task not found.")
        }
        let created = try await IssueQueries.createIssue(db, .init(spaceId: parent.spaceId, title: trimmed, parentId: parentId))
        return created.toRecord()
    }

    /// Bulk variant for the "Generate ✦" AI flow.
    public static func createSubtasksFromTitles(_ db: ZenithDatabase, parentId: UUID, titles: [String]) async throws -> [IssueRecord] {
        let cleanTitles = titles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleanTitles.isEmpty else { return [] }
        guard let parent = try await IssueQueries.getIssueById(db, id: parentId) else {
            throw ValidationError(field: "parentId", message: "Parent task not found.")
        }
        let drafts = cleanTitles.map { IssueQueries.NewIssueInput(spaceId: parent.spaceId, title: $0, parentId: parentId) }
        let created = try await IssueQueries.createIssues(db, spaceId: parent.spaceId, drafts: drafts)
        return created.toRecords()
    }

    /// Links/unlinks a task to a parent — `parentId: nil` promotes it back
    /// to a standalone task. Guarded against creating a cycle (a task can't
    /// become an ancestor of its own ancestor).
    public static func setParent(_ db: ZenithDatabase, id: UUID, parentId: UUID?) async throws {
        if let parentId {
            guard parentId != id else { throw ValidationError(field: "parentId", message: "A task can't be its own subtask.") }
            if try await IssueQueries.wouldCreateCycle(db, taskId: id, candidateParentId: parentId) {
                throw ValidationError(field: "parentId", message: "That would create a loop of subtasks.")
            }
        }
        _ = try await IssueQueries.updateIssueFields(db, id: id, patch: IssueFieldPatch(parentId: .some(parentId)))
    }

    /// Live search backing the drawer's "Link existing…" picker — derives
    /// `spaceId` from the task being edited so callers only need to pass ids.
    public static func searchIssuesForSubtask(_ db: ZenithDatabase, taskId: UUID, query: String) async throws -> [(id: UUID, title: String)] {
        guard let task = try await IssueQueries.getIssueById(db, id: taskId) else { return [] }
        return try await IssueQueries.searchIssuesForSpace(db, spaceId: task.spaceId, query: query, excludeIds: [taskId])
    }
}
