import Foundation
import PostgresNIO

/// Port of `lib/db/queries/issues.ts`.
public enum IssueQueries {
    // `due_date`/`start_date` are Postgres `date` columns — casting to
    // `::text` here is required, not cosmetic: without it, PostgresNIO's
    // generic `String` decoder reads the column's raw binary `date`
    // representation (a 4-byte day-offset integer) as if it were UTF-8
    // text, producing garbage characters instead of throwing a decode
    // error. Casting to `text` in SQL makes Postgres send an actual
    // "YYYY-MM-DD" string over the wire, which decodes correctly.
    private static let columns = """
        id, space_id, milestone_id, parent_id, title, description, status, is_closed, priority, \
        tags, branch, estimate, due_date::text AS due_date, start_date::text AS start_date, \
        custom_field_values, position, closed_at, created_at, updated_at
        """

    private static func map(_ row: PostgresRow) throws -> Issue {
        let r = row.makeRandomAccess()
        return Issue(
            id: try r["id"].decode(UUID.self),
            spaceId: try r["space_id"].decode(UUID.self),
            milestoneId: try r["milestone_id"].decode(UUID?.self),
            parentId: try r["parent_id"].decode(UUID?.self),
            title: try r["title"].decode(String.self),
            description: try r["description"].decode(String?.self),
            status: try r["status"].decodeEnum(IssueStatus.self),
            isClosed: try r["is_closed"].decode(Bool.self),
            priority: try r["priority"].decodeEnum(IssuePriority.self),
            tags: try r["tags"].decode([String].self),
            branch: try r["branch"].decode(String?.self),
            estimate: try r["estimate"].decode(String?.self),
            dueDate: try r["due_date"].decode(String?.self),
            startDate: try r["start_date"].decode(String?.self),
            customFieldValues: try r["custom_field_values"].decode([String: AnyCodableValue].self),
            position: try r["position"].decode(Double.self),
            closedAt: try r["closed_at"].decode(Date?.self),
            createdAt: try r["created_at"].decode(Date.self),
            updatedAt: try r["updated_at"].decode(Date.self)
        )
    }

    // MARK: - Reads

    public static func getIssuesForSpace(_ db: ZenithDatabase, spaceId: UUID) async throws -> [Issue] {
        let rows = try await db.query("""
            SELECT \(unescaped: columns) FROM issues WHERE space_id = \(spaceId)
            ORDER BY status ASC, position ASC, created_at DESC
            """)
        var results: [Issue] = []
        for try await row in rows { results.append(try map(row)) }
        return results
    }

    public static func getIssuesForMilestone(_ db: ZenithDatabase, milestoneId: UUID) async throws -> [Issue] {
        let rows = try await db.query("""
            SELECT \(unescaped: columns) FROM issues WHERE milestone_id = \(milestoneId)
            ORDER BY status ASC, position ASC
            """)
        var results: [Issue] = []
        for try await row in rows { results.append(try map(row)) }
        return results
    }

    public static func getIssueById(_ db: ZenithDatabase, id: UUID) async throws -> Issue? {
        let rows = try await db.query("SELECT \(unescaped: columns) FROM issues WHERE id = \(id) LIMIT 1")
        for try await row in rows { return try map(row) }
        return nil
    }

    /// Repo ids linked to each of `issueIds`, batched into one query.
    public static func repoIds(_ db: ZenithDatabase, forIssueIds issueIds: [UUID]) async throws -> [UUID: [UUID]] {
        var map: [UUID: [UUID]] = [:]
        guard !issueIds.isEmpty else { return map }
        let rows = try await db.query("SELECT issue_id, repo_id FROM issue_repos WHERE issue_id = ANY(\(issueIds))")
        for try await row in rows {
            let r = row.makeRandomAccess()
            let issueId = try r["issue_id"].decode(UUID.self)
            let repoId = try r["repo_id"].decode(UUID.self)
            map[issueId, default: []].append(repoId)
        }
        return map
    }

    /// `{total, done}` per parent, for every id in `parentIds`, in one query.
    public static func subtaskCounts(_ db: ZenithDatabase, forParentIds parentIds: [UUID]) async throws -> [UUID: SubtaskCount] {
        var map: [UUID: SubtaskCount] = [:]
        guard !parentIds.isEmpty else { return map }
        let rows = try await db.query("SELECT parent_id, is_closed FROM issues WHERE parent_id = ANY(\(parentIds))")
        for try await row in rows {
            let r = row.makeRandomAccess()
            guard let parentId = try r["parent_id"].decode(UUID?.self) else { continue }
            let isClosed = try r["is_closed"].decode(Bool.self)
            var entry = map[parentId] ?? .zero
            entry.total += 1
            if isClosed { entry.done += 1 }
            map[parentId] = entry
        }
        return map
    }

    /// A task's immediate children, for rendering the drawer's subtask list.
    public static func getChildIssues(_ db: ZenithDatabase, parentId: UUID) async throws -> [Issue] {
        let rows = try await db.query("""
            SELECT \(unescaped: columns) FROM issues WHERE parent_id = \(parentId)
            ORDER BY position ASC, created_at ASC
            """)
        var results: [Issue] = []
        for try await row in rows { results.append(try map(row)) }
        return results
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
        let rows: PostgresRowSequence
        if excludeIds.isEmpty {
            rows = try await db.query("""
                SELECT id, title FROM issues WHERE space_id = \(spaceId) AND title ILIKE \(pattern)
                ORDER BY title ASC LIMIT 20
                """)
        } else {
            rows = try await db.query("""
                SELECT id, title FROM issues WHERE space_id = \(spaceId) AND title ILIKE \(pattern)
                AND NOT (id = ANY(\(excludeIds))) ORDER BY title ASC LIMIT 20
                """)
        }
        var results: [(id: UUID, title: String)] = []
        for try await row in rows {
            let r = row.makeRandomAccess()
            results.append((id: try r["id"].decode(UUID.self), title: try r["title"].decode(String.self)))
        }
        return results
    }

    /// Highest `position` per status column in a space.
    public static func maxPositionsBySpace(_ db: ZenithDatabase, spaceId: UUID) async throws -> [IssueStatus: Double] {
        let rows = try await db.query("""
            SELECT status, max(position) AS value FROM issues WHERE space_id = \(spaceId) GROUP BY status
            """)
        var map: [IssueStatus: Double] = [:]
        for try await row in rows {
            let r = row.makeRandomAccess()
            if let status = try r["status"].decodeEnum(IssueStatus?.self), let value = try r["value"].decode(Double?.self) {
                map[status] = value
            }
        }
        return map
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
        let rows = try await db.query("SELECT milestone_id, is_closed FROM issues WHERE space_id = \(spaceId)")
        var map: [UUID: MilestoneProgress] = [:]
        for try await row in rows {
            let r = row.makeRandomAccess()
            guard let milestoneId = try r["milestone_id"].decode(UUID?.self) else { continue }
            let isClosed = try r["is_closed"].decode(Bool.self)
            var entry = map[milestoneId] ?? MilestoneProgress(total: 0, closed: 0)
            entry.total += 1
            if isClosed { entry.closed += 1 }
            map[milestoneId] = entry
        }
        return map
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
        let rows = try await db.query("SELECT space_id, is_closed FROM issues")
        var map: [UUID: SpaceIssueCounts] = [:]
        for try await row in rows {
            let r = row.makeRandomAccess()
            let spaceId = try r["space_id"].decode(UUID.self)
            let isClosed = try r["is_closed"].decode(Bool.self)
            var entry = map[spaceId] ?? SpaceIssueCounts(total: 0, open: 0)
            entry.total += 1
            if !isClosed { entry.open += 1 }
            map[spaceId] = entry
        }
        return map
    }

    public static func unassignedIssueCount(_ db: ZenithDatabase, spaceId: UUID) async throws -> Int {
        let rows = try await db.query("SELECT id FROM issues WHERE space_id = \(spaceId) AND milestone_id IS NULL")
        var count = 0
        for try await _ in rows { count += 1 }
        return count
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
    /// excluded.
    public static func upcomingIssues(_ db: ZenithDatabase, daysAhead: Int) async throws -> [UpcomingIssue] {
        let cutoffDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: daysAhead, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let cutoffString = formatter.string(from: cutoffDate)

        // `due_date` is a Postgres `date` column; PostgresNIO binds a
        // Swift `String` parameter as `text`, and Postgres won't coerce a
        // `text`-typed parameter to `date` in any context — comparison
        // (`date <= text`) or assignment (`SET due_date = $1`) alike. Every
        // `due_date` read casts the column with `::text`, every write casts
        // the parameter with `::date`.
        let rows = try await db.query("""
            SELECT i.id, i.title, i.priority, i.status, i.due_date::text AS due_date, s.name AS space_name, s.slug AS space_slug
            FROM issues i INNER JOIN spaces s ON i.space_id = s.id
            WHERE i.due_date IS NOT NULL AND i.due_date <= \(cutoffString)::date AND i.status != 'done'
            ORDER BY i.due_date ASC LIMIT 20
            """)
        var results: [UpcomingIssue] = []
        for try await row in rows {
            let r = row.makeRandomAccess()
            results.append(UpcomingIssue(
                id: try r["id"].decode(UUID.self),
                title: try r["title"].decode(String.self),
                priority: try r["priority"].decodeEnum(IssuePriority.self),
                status: try r["status"].decodeEnum(IssueStatus.self),
                dueDate: try r["due_date"].decode(String?.self),
                spaceName: try r["space_name"].decode(String.self),
                spaceSlug: try r["space_slug"].decode(String.self)
            ))
        }
        return results
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

    public static func createIssue(_ db: ZenithDatabase, _ input: NewIssueInput) async throws -> Issue {
        let rows = try await db.query("SELECT max(position) AS value FROM issues WHERE space_id = \(input.spaceId) AND status = \(input.status.rawValue)")
        var maxPosition: Double?
        for try await row in rows { maxPosition = try row.makeRandomAccess()["value"].decode(Double?.self) }
        let position = Position.atEnd(maxPosition)
        let isClosed = input.status == .done
        let closedAt: Date? = isClosed ? Date() : nil

        let insertRows = try await db.query("""
            INSERT INTO issues (
                space_id, title, description, status, is_closed, closed_at, priority, tags, branch,
                estimate, parent_id, milestone_id, due_date, start_date, custom_field_values, position
            ) VALUES (
                \(input.spaceId), \(input.title), \(input.description), \(input.status.rawValue), \(isClosed),
                \(closedAt), \(input.priority.rawValue), \(input.tags), \(input.branch), \(input.estimate),
                \(input.parentId), \(input.milestoneId), \(input.dueDate)::date, \(input.startDate)::date,
                \(input.customFieldValues), \(position)
            ) RETURNING \(unescaped: columns)
            """)
        var created: Issue?
        for try await row in insertRows { created = try map(row) }
        guard let created else { throw DatabaseError.insertReturnedNoRow }

        if !input.repoIds.isEmpty {
            try await linkRepos(db, issueId: created.id, repoIds: input.repoIds)
        }
        return created
    }

    /// Bulk "paste a list" flow: creates many backlog issues in one insert,
    /// positions threaded forward in memory so the list lands in the order
    /// it was reviewed in, appended after whatever's already at the end of
    /// the backlog.
    public static func createIssues(_ db: ZenithDatabase, spaceId: UUID, drafts: [NewIssueInput]) async throws -> [Issue] {
        guard !drafts.isEmpty else { return [] }

        let rows = try await db.query("SELECT max(position) AS value FROM issues WHERE space_id = \(spaceId) AND status = 'backlog'")
        var position: Double?
        for try await row in rows { position = try row.makeRandomAccess()["value"].decode(Double?.self) }

        var created: [Issue] = []
        for draft in drafts {
            position = Position.atEnd(position)
            let insertRows = try await db.query("""
                INSERT INTO issues (
                    space_id, title, description, status, is_closed, priority, tags, branch,
                    estimate, parent_id, milestone_id, due_date, custom_field_values, position
                ) VALUES (
                    \(spaceId), \(draft.title), \(draft.description), 'backlog', false, \(draft.priority.rawValue),
                    \(draft.tags), \(draft.branch), \(draft.estimate), \(draft.parentId), \(draft.milestoneId),
                    \(draft.dueDate)::date, \(draft.customFieldValues), \(position!)
                ) RETURNING \(unescaped: columns)
                """)
            for try await row in insertRows {
                let issue = try map(row)
                created.append(issue)
                if !draft.repoIds.isEmpty { try await linkRepos(db, issueId: issue.id, repoIds: draft.repoIds) }
            }
        }
        return created
    }

    private static func linkRepos(_ db: ZenithDatabase, issueId: UUID, repoIds: [UUID]) async throws {
        guard !repoIds.isEmpty else { return }
        for repoId in repoIds {
            try await db.execute("INSERT INTO issue_repos (issue_id, repo_id) VALUES (\(issueId), \(repoId))")
        }
    }

    /// Generic per-field autosave. Keeps `isClosed`/`closedAt` in sync
    /// whenever `status` is part of the patch — there's no separate close/
    /// reopen action, "done" status is the source of truth.
    /// `customFieldValues`, if present, is merged into the existing jsonb
    /// via Postgres's `||` object-concat operator rather than overwriting.
    /// Wrapped in a transaction alongside the repo-link full-replace, same
    /// as the TS side's `db.transaction(...)`.
    public static func updateIssueFields(_ db: ZenithDatabase, id: UUID, patch: IssueFieldPatch) async throws -> Issue? {
        try await db.withTransaction { connection in
            var update = DynamicUpdate()

            if let title = patch.title { try update.set("title", title) }
            if case .some(let description) = patch.description {
                if let description { try update.set("description", description) } else { update.setNull("description") }
            }
            if let status = patch.status {
                try update.set("status", status.rawValue)
                try update.set("is_closed", status == .done)
                if status == .done { try update.set("closed_at", Date()) } else { update.setNull("closed_at") }
            }
            if let priority = patch.priority { try update.set("priority", priority.rawValue) }
            if let tags = patch.tags { try update.set("tags", tags) }
            if case .some(let branch) = patch.branch {
                if let branch { try update.set("branch", branch) } else { update.setNull("branch") }
            }
            if case .some(let estimate) = patch.estimate {
                if let estimate { try update.set("estimate", estimate) } else { update.setNull("estimate") }
            }
            if case .some(let parentId) = patch.parentId {
                if let parentId { try update.set("parent_id", parentId) } else { update.setNull("parent_id") }
            }
            if case .some(let milestoneId) = patch.milestoneId {
                if let milestoneId { try update.set("milestone_id", milestoneId) } else { update.setNull("milestone_id") }
            }
            // `due_date`/`start_date` are Postgres `date` columns and
            // PostgresNIO binds a Swift `String` parameter as `text`.
            // Postgres will not coerce a `text`-typed parameter to `date`
            // even in an assignment context (only a truly *unknown* literal
            // gets that treatment), so the `::date` cast is required — its
            // absence is what raised `42804: column "due_date" is of type
            // date but expression is of type text`.
            if case .some(let dueDate) = patch.dueDate {
                if let dueDate { try update.set("due_date", raw: "$1::date", binding: dueDate) } else { update.setNull("due_date") }
            }
            if case .some(let startDate) = patch.startDate {
                if let startDate { try update.set("start_date", raw: "$1::date", binding: startDate) } else { update.setNull("start_date") }
            }
            if let position = patch.position { try update.set("position", position) }
            if let customFieldValues = patch.customFieldValues {
                try update.set("custom_field_values", raw: "custom_field_values || $1::jsonb", binding: customFieldValues)
            }

            let query = try update.buildQuery(table: "issues", whereIdEquals: id, returning: columns)
            let rows = try await connection.query(query, logger: await db.logger)
            var updated: Issue?
            for try await row in rows { updated = try map(row) }

            if let repoIds = patch.repoIds {
                try await connection.query("DELETE FROM issue_repos WHERE issue_id = \(id)", logger: await db.logger)
                for repoId in repoIds {
                    try await connection.query(
                        "INSERT INTO issue_repos (issue_id, repo_id) VALUES (\(id), \(repoId))", logger: await db.logger
                    )
                }
            }

            return updated
        }
    }

    public static func deleteIssue(_ db: ZenithDatabase, id: UUID) async throws {
        try await db.execute("DELETE FROM issues WHERE id = \(id)")
    }

    public static func bulkUpdateStatus(_ db: ZenithDatabase, ids: [UUID], status: IssueStatus) async throws {
        guard !ids.isEmpty else { return }
        let isClosed = status == .done
        if isClosed {
            try await db.execute("""
                UPDATE issues SET status = \(status.rawValue), is_closed = true, closed_at = now(), updated_at = now()
                WHERE id = ANY(\(ids))
                """)
        } else {
            try await db.execute("""
                UPDATE issues SET status = \(status.rawValue), is_closed = false, closed_at = NULL, updated_at = now()
                WHERE id = ANY(\(ids))
                """)
        }
    }

    public static func bulkUpdatePriority(_ db: ZenithDatabase, ids: [UUID], priority: IssuePriority) async throws {
        guard !ids.isEmpty else { return }
        try await db.execute("UPDATE issues SET priority = \(priority.rawValue), updated_at = now() WHERE id = ANY(\(ids))")
    }

    public static func bulkDeleteIssues(_ db: ZenithDatabase, ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await db.execute("DELETE FROM issues WHERE id = ANY(\(ids))")
    }
}
