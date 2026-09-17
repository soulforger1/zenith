import Foundation
import GRDB

/// Local-store queries for the `issues` table.
public enum IssueQueries {
    private static func map(_ row: Row) throws -> Issue {
        Issue(
            id: try row.requireUUID("id"),
            spaceId: try row.requireUUID("space_id"),
            milestoneId: try row.optionalUUID("milestone_id"),
            parentId: try row.optionalUUID("parent_id"),
            title: try row.requireString("title"),
            description: row.optionalString("description"),
            status: try row.requireEnum("status", IssueStatus.self),
            isClosed: row.requireBool("is_closed"),
            priority: try row.requireEnum("priority", IssuePriority.self),
            tags: try row.jsonStringArray("tags"),
            branch: row.optionalString("branch"),
            estimate: row.optionalString("estimate"),
            dueDate: row.optionalString("due_date"),
            startDate: row.optionalString("start_date"),
            customFieldValues: try row.jsonMap("custom_field_values"),
            position: try row.requireDouble("position"),
            closedAt: row.optionalDate("closed_at"),
            createdAt: try row.requireDate("created_at"),
            updatedAt: try row.requireDate("updated_at")
        )
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    // MARK: - Reads

    public static func getIssuesForSpace(_ db: ZenithDatabase, spaceId: UUID) async throws -> [Issue] {
        try await db.read { d in
            try Row.fetchAll(
                d, sql: "SELECT * FROM issues WHERE space_id = ? ORDER BY status ASC, position ASC, created_at DESC",
                arguments: [spaceId.databaseText]
            ).map(map)
        }
    }

    public static func getIssuesForMilestone(_ db: ZenithDatabase, milestoneId: UUID) async throws -> [Issue] {
        try await db.read { d in
            try Row.fetchAll(
                d, sql: "SELECT * FROM issues WHERE milestone_id = ? ORDER BY status ASC, position ASC",
                arguments: [milestoneId.databaseText]
            ).map(map)
        }
    }

    public static func getIssueById(_ db: ZenithDatabase, id: UUID) async throws -> Issue? {
        try await db.read { d in
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM issues WHERE id = ? LIMIT 1", arguments: [id.databaseText]) else {
                return nil
            }
            return try map(row)
        }
    }

    /// Repo ids linked to each of `issueIds`, batched into one query.
    public static func repoIds(_ db: ZenithDatabase, forIssueIds issueIds: [UUID]) async throws -> [UUID: [UUID]] {
        guard !issueIds.isEmpty else { return [:] }
        return try await db.read { d in
            let rows = try Row.fetchAll(
                d, sql: "SELECT issue_id, repo_id FROM issue_repos WHERE issue_id IN (\(placeholders(issueIds.count)))",
                arguments: StatementArguments(issueIds.map { $0.databaseText })
            )
            var map: [UUID: [UUID]] = [:]
            for row in rows {
                let issueId = try row.requireUUID("issue_id")
                let repoId = try row.requireUUID("repo_id")
                map[issueId, default: []].append(repoId)
            }
            return map
        }
    }

    /// `{total, done}` per parent, for every id in `parentIds`, in one query.
    public static func subtaskCounts(_ db: ZenithDatabase, forParentIds parentIds: [UUID]) async throws -> [UUID: SubtaskCount] {
        guard !parentIds.isEmpty else { return [:] }
        return try await db.read { d in
            let rows = try Row.fetchAll(
                d, sql: "SELECT parent_id, is_closed FROM issues WHERE parent_id IN (\(placeholders(parentIds.count)))",
                arguments: StatementArguments(parentIds.map { $0.databaseText })
            )
            var map: [UUID: SubtaskCount] = [:]
            for row in rows {
                guard let parentId = try row.optionalUUID("parent_id") else { continue }
                var entry = map[parentId] ?? .zero
                entry.total += 1
                if row.requireBool("is_closed") { entry.done += 1 }
                map[parentId] = entry
            }
            return map
        }
    }

    /// A task's immediate children, for rendering the drawer's subtask list.
    public static func getChildIssues(_ db: ZenithDatabase, parentId: UUID) async throws -> [Issue] {
        try await db.read { d in
            try Row.fetchAll(
                d, sql: "SELECT * FROM issues WHERE parent_id = ? ORDER BY position ASC, created_at ASC",
                arguments: [parentId.databaseText]
            ).map(map)
        }
    }

    /// True if setting `candidateParentId` as `taskId`'s parent would create
    /// a cycle — walks `candidateParentId`'s ancestor chain looking for
    /// `taskId`, capped at 50 hops so a data bug can't spin this forever.
    public static func wouldCreateCycle(_ db: ZenithDatabase, taskId: UUID, candidateParentId: UUID) async throws -> Bool {
        var current: UUID? = candidateParentId
        var hops = 0
        while let currentId = current, hops < 50 {
            if currentId == taskId { return true }
            let issue = try await getIssueById(db, id: currentId)
            current = issue?.parentId
            hops += 1
        }
        return false
    }

    /// Title search within a space, for the "link existing task as subtask"
    /// picker.
    public static func searchIssuesForSpace(
        _ db: ZenithDatabase, spaceId: UUID, query: String, excludeIds: [UUID] = []
    ) async throws -> [(id: UUID, title: String)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let pattern = "%\(trimmed)%"
        return try await db.read { d in
            let rows: [Row]
            if excludeIds.isEmpty {
                rows = try Row.fetchAll(
                    d, sql: "SELECT id, title FROM issues WHERE space_id = ? AND title LIKE ? ORDER BY title ASC LIMIT 20",
                    arguments: [spaceId.databaseText, pattern]
                )
            } else {
                var arguments: [(any DatabaseValueConvertible)?] = [spaceId.databaseText, pattern]
                arguments.append(contentsOf: excludeIds.map { $0.databaseText })
                rows = try Row.fetchAll(
                    d, sql: """
                        SELECT id, title FROM issues WHERE space_id = ? AND title LIKE ?
                        AND id NOT IN (\(placeholders(excludeIds.count))) ORDER BY title ASC LIMIT 20
                        """,
                    arguments: StatementArguments(arguments)
                )
            }
            return try rows.map { (id: try $0.requireUUID("id"), title: try $0.requireString("title")) }
        }
    }

    /// Highest `position` per status column in a space.
    public static func maxPositionsBySpace(_ db: ZenithDatabase, spaceId: UUID) async throws -> [IssueStatus: Double] {
        try await db.read { d in
            let rows = try Row.fetchAll(
                d, sql: "SELECT status, max(position) AS value FROM issues WHERE space_id = ? GROUP BY status",
                arguments: [spaceId.databaseText]
            )
            var map: [IssueStatus: Double] = [:]
            for row in rows {
                if let status = try row.optionalEnum("status", IssueStatus.self), let value = row["value"] as Double? {
                    map[status] = value
                }
            }
            return map
        }
    }

    public struct MilestoneProgress: Sendable, Equatable {
        public var total: Int
        public var closed: Int

        public init(total: Int, closed: Int) {
            self.total = total
            self.closed = closed
        }
    }

    /// Progress counts for every milestone in a space, in one query.
    public static func milestoneProgress(_ db: ZenithDatabase, spaceId: UUID) async throws -> [UUID: MilestoneProgress] {
        try await db.read { d in
            let rows = try Row.fetchAll(d, sql: "SELECT milestone_id, is_closed FROM issues WHERE space_id = ?", arguments: [spaceId.databaseText])
            var map: [UUID: MilestoneProgress] = [:]
            for row in rows {
                guard let milestoneId = try row.optionalUUID("milestone_id") else { continue }
                var entry = map[milestoneId] ?? MilestoneProgress(total: 0, closed: 0)
                entry.total += 1
                if row.requireBool("is_closed") { entry.closed += 1 }
                map[milestoneId] = entry
            }
            return map
        }
    }

    public struct SpaceIssueCounts: Sendable, Equatable {
        public var total: Int
        public var open: Int

        public init(total: Int, open: Int) {
            self.total = total
            self.open = open
        }
    }

    /// Open/total issue counts for every space, in one query.
    public static func issueCountsBySpace(_ db: ZenithDatabase) async throws -> [UUID: SpaceIssueCounts] {
        try await db.read { d in
            let rows = try Row.fetchAll(d, sql: "SELECT space_id, is_closed FROM issues")
            var map: [UUID: SpaceIssueCounts] = [:]
            for row in rows {
                let spaceId = try row.requireUUID("space_id")
                var entry = map[spaceId] ?? SpaceIssueCounts(total: 0, open: 0)
                entry.total += 1
                if !row.requireBool("is_closed") { entry.open += 1 }
                map[spaceId] = entry
            }
            return map
        }
    }

    public static func unassignedIssueCount(_ db: ZenithDatabase, spaceId: UUID) async throws -> Int {
        try await db.read { d in
            try Int.fetchOne(
                d, sql: "SELECT COUNT(*) FROM issues WHERE space_id = ? AND milestone_id IS NULL", arguments: [spaceId.databaseText]
            ) ?? 0
        }
    }

    public struct UpcomingIssue: Sendable, Identifiable, Equatable {
        public let id: UUID
        public let title: String
        public let priority: IssuePriority
        public let status: IssueStatus
        public let dueDate: String?
        public let spaceName: String
        public let spaceSlug: String
    }

    /// Cross-space "due soon" feed for the spaces home page's "Upcoming"
    /// widget — overdue tasks and tasks due within `daysAhead`, done tasks
    /// excluded. `due_date` is plain `"YYYY-MM-DD"` text now, so the cutoff
    /// is computed the same way (`ISODate`, local-timezone midnight) and
    /// compared lexically — no more Postgres date/text cast juggling.
    public static func upcomingIssues(_ db: ZenithDatabase, daysAhead: Int) async throws -> [UpcomingIssue] {
        let cutoff = ISODate.addDays(ISODate.today(), daysAhead)
        return try await db.read { d in
            let rows = try Row.fetchAll(
                d, sql: """
                    SELECT i.id AS id, i.title AS title, i.priority AS priority, i.status AS status,
                           i.due_date AS due_date, s.name AS space_name, s.slug AS space_slug
                    FROM issues i INNER JOIN spaces s ON i.space_id = s.id
                    WHERE i.due_date IS NOT NULL AND i.due_date <= ? AND i.status != 'done'
                    ORDER BY i.due_date ASC LIMIT 20
                    """,
                arguments: [cutoff]
            )
            return try rows.map { row in
                UpcomingIssue(
                    id: try row.requireUUID("id"),
                    title: try row.requireString("title"),
                    priority: try row.requireEnum("priority", IssuePriority.self),
                    status: try row.requireEnum("status", IssueStatus.self),
                    dueDate: row.optionalString("due_date"),
                    spaceName: try row.requireString("space_name"),
                    spaceSlug: try row.requireString("space_slug")
                )
            }
        }
    }

    // MARK: - Writes

    public struct NewIssueInput: Sendable {
        public var spaceId: UUID
        public var title: String
        public var description: String?
        public var status: IssueStatus
        public var priority: IssuePriority
        public var tags: [String]
        public var branch: String?
        public var estimate: String?
        public var parentId: UUID?
        public var milestoneId: UUID?
        public var repoIds: [UUID]
        public var dueDate: String?
        public var startDate: String?
        public var customFieldValues: [String: AnyCodableValue]

        public init(
            spaceId: UUID, title: String, description: String? = nil, status: IssueStatus = .backlog,
            priority: IssuePriority = .medium, tags: [String] = [], branch: String? = nil,
            estimate: String? = nil, parentId: UUID? = nil, milestoneId: UUID? = nil,
            repoIds: [UUID] = [], dueDate: String? = nil, startDate: String? = nil,
            customFieldValues: [String: AnyCodableValue] = [:]
        ) {
            self.spaceId = spaceId
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
            self.customFieldValues = customFieldValues
        }
    }

    /// Links `repoIds` to `issueId` — runs inside the caller's write
    /// transaction (a plain `Database`, not a `ZenithDatabase`).
    private static func linkRepos(_ d: Database, issueId: UUID, repoIds: [UUID]) throws {
        guard !repoIds.isEmpty else { return }
        let now = Date()
        for repoId in repoIds {
            try d.execute(
                sql: "INSERT INTO issue_repos (id, issue_id, repo_id, updated_at) VALUES (?, ?, ?, ?)",
                arguments: [UUID().databaseText, issueId.databaseText, repoId.databaseText, now]
            )
        }
    }

    public static func createIssue(_ db: ZenithDatabase, _ input: NewIssueInput) async throws -> Issue {
        try await db.write { d in
            let maxPosition = try Double.fetchOne(
                d, sql: "SELECT max(position) FROM issues WHERE space_id = ? AND status = ?",
                arguments: [input.spaceId.databaseText, input.status.rawValue]
            )
            let position = Position.atEnd(maxPosition)
            let isClosed = input.status == .done
            let now = Date()
            let id = UUID()

            try d.execute(
                sql: """
                    INSERT INTO issues (
                        id, space_id, title, description, status, is_closed, closed_at, priority, tags, branch,
                        estimate, parent_id, milestone_id, due_date, start_date, custom_field_values, position,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    id.databaseText, input.spaceId.databaseText, input.title, input.description, input.status.rawValue,
                    isClosed, isClosed ? now : nil, input.priority.rawValue, try JSONColumn.encodeStringArray(input.tags),
                    input.branch, input.estimate, input.parentId?.databaseText, input.milestoneId?.databaseText,
                    input.dueDate, input.startDate, try JSONColumn.encodeMap(input.customFieldValues), position, now, now,
                ]
            )
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM issues WHERE id = ?", arguments: [id.databaseText]) else {
                throw StoreError.insertReturnedNoRow
            }
            let created = try map(row)

            if !input.repoIds.isEmpty {
                try linkRepos(d, issueId: created.id, repoIds: input.repoIds)
            }
            return created
        }
    }

    /// Bulk "paste a list" flow: creates many backlog issues in one write
    /// transaction, positions threaded forward in memory so the list lands
    /// in the order it was reviewed in, appended after whatever's already
    /// at the end of the backlog.
    public static func createIssues(_ db: ZenithDatabase, spaceId: UUID, drafts: [NewIssueInput]) async throws -> [Issue] {
        guard !drafts.isEmpty else { return [] }
        return try await db.write { d in
            var position = try Double.fetchOne(
                d, sql: "SELECT max(position) FROM issues WHERE space_id = ? AND status = 'backlog'", arguments: [spaceId.databaseText]
            )
            var created: [Issue] = []
            for draft in drafts {
                position = Position.atEnd(position)
                let id = UUID()
                let now = Date()
                try d.execute(
                    sql: """
                        INSERT INTO issues (
                            id, space_id, title, description, status, is_closed, priority, tags, branch,
                            estimate, parent_id, milestone_id, due_date, custom_field_values, position,
                            created_at, updated_at
                        ) VALUES (?, ?, ?, ?, 'backlog', 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        id.databaseText, spaceId.databaseText, draft.title, draft.description, draft.priority.rawValue,
                        try JSONColumn.encodeStringArray(draft.tags), draft.branch, draft.estimate,
                        draft.parentId?.databaseText, draft.milestoneId?.databaseText, draft.dueDate,
                        try JSONColumn.encodeMap(draft.customFieldValues), position!, now, now,
                    ]
                )
                guard let row = try Row.fetchOne(d, sql: "SELECT * FROM issues WHERE id = ?", arguments: [id.databaseText]) else {
                    throw StoreError.insertReturnedNoRow
                }
                let issue = try map(row)
                created.append(issue)
                if !draft.repoIds.isEmpty { try linkRepos(d, issueId: issue.id, repoIds: draft.repoIds) }
            }
            return created
        }
    }

    /// Generic per-field autosave. Keeps `isClosed`/`closedAt` in sync
    /// whenever `status` is part of the patch — there's no separate close/
    /// reopen action, "done" status is the source of truth.
    /// `customFieldValues`, if present, is merged into the existing map
    /// (Swift-side read-modify-write, in the same write transaction)
    /// rather than overwriting. Wrapped in a single `db.write { }`, which
    /// is itself a transaction, alongside the repo-link full-replace.
    /// `updated_at` is always bumped, even for a repo-only patch — the
    /// sync layer (Phase 2+) relies on every local write touching it.
    public static func updateIssueFields(_ db: ZenithDatabase, id: UUID, patch: IssueFieldPatch) async throws -> Issue? {
        try await db.write { d in
            var update = DynamicUpdate()

            if let title = patch.title { update.set("title", title) }
            if case .some(let description) = patch.description {
                if let description { update.set("description", description) } else { update.setNull("description") }
            }
            if let status = patch.status {
                update.set("status", status.rawValue)
                update.set("is_closed", status == .done)
                if status == .done { update.set("closed_at", Date()) } else { update.setNull("closed_at") }
            }
            if let priority = patch.priority { update.set("priority", priority.rawValue) }
            if let tags = patch.tags { update.set("tags", try JSONColumn.encodeStringArray(tags)) }
            if case .some(let branch) = patch.branch {
                if let branch { update.set("branch", branch) } else { update.setNull("branch") }
            }
            if case .some(let estimate) = patch.estimate {
                if let estimate { update.set("estimate", estimate) } else { update.setNull("estimate") }
            }
            if case .some(let parentId) = patch.parentId {
                if let parentId { update.set("parent_id", parentId.databaseText) } else { update.setNull("parent_id") }
            }
            if case .some(let milestoneId) = patch.milestoneId {
                if let milestoneId { update.set("milestone_id", milestoneId.databaseText) } else { update.setNull("milestone_id") }
            }
            // `due_date`/`start_date` are plain TEXT now — no Postgres
            // `::date` cast needed (that whole bug class, commits
            // `61561a6`/`abd5047`, is gone with the move off Postgres).
            if case .some(let dueDate) = patch.dueDate {
                if let dueDate { update.set("due_date", dueDate) } else { update.setNull("due_date") }
            }
            if case .some(let startDate) = patch.startDate {
                if let startDate { update.set("start_date", startDate) } else { update.setNull("start_date") }
            }
            if let position = patch.position { update.set("position", position) }
            if let partial = patch.customFieldValues {
                let currentText = try String.fetchOne(d, sql: "SELECT custom_field_values FROM issues WHERE id = ?", arguments: [id.databaseText])
                var current = try JSONColumn.decodeMap(currentText)
                current.merge(partial) { _, new in new }
                update.set("custom_field_values", try JSONColumn.encodeMap(current))
            }

            guard let row = try update.execute(d, table: "issues", id: id.databaseText) else { return nil }
            let updated = try map(row)

            if let repoIds = patch.repoIds {
                try d.execute(sql: "DELETE FROM issue_repos WHERE issue_id = ?", arguments: [id.databaseText])
                try linkRepos(d, issueId: id, repoIds: repoIds)
            }

            return updated
        }
    }

    public static func deleteIssue(_ db: ZenithDatabase, id: UUID) async throws {
        try await db.write { d in
            try d.execute(sql: "DELETE FROM issues WHERE id = ?", arguments: [id.databaseText])
        }
    }

    public static func bulkUpdateStatus(_ db: ZenithDatabase, ids: [UUID], status: IssueStatus) async throws {
        guard !ids.isEmpty else { return }
        try await db.write { d in
            let now = Date()
            let isClosed = status == .done
            var arguments: [(any DatabaseValueConvertible)?] = [status.rawValue, isClosed, isClosed ? now : nil, now]
            arguments.append(contentsOf: ids.map { $0.databaseText })
            try d.execute(
                sql: "UPDATE issues SET status = ?, is_closed = ?, closed_at = ?, updated_at = ? WHERE id IN (\(placeholders(ids.count)))",
                arguments: StatementArguments(arguments)
            )
        }
    }

    public static func bulkUpdatePriority(_ db: ZenithDatabase, ids: [UUID], priority: IssuePriority) async throws {
        guard !ids.isEmpty else { return }
        try await db.write { d in
            var arguments: [(any DatabaseValueConvertible)?] = [priority.rawValue, Date()]
            arguments.append(contentsOf: ids.map { $0.databaseText })
            try d.execute(
                sql: "UPDATE issues SET priority = ?, updated_at = ? WHERE id IN (\(placeholders(ids.count)))",
                arguments: StatementArguments(arguments)
            )
        }
    }

    public static func bulkDeleteIssues(_ db: ZenithDatabase, ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await db.write { d in
            try d.execute(
                sql: "DELETE FROM issues WHERE id IN (\(placeholders(ids.count)))",
                arguments: StatementArguments(ids.map { $0.databaseText })
            )
        }
    }
}
