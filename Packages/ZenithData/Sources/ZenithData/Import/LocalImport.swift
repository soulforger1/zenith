import Foundation
import GRDB

/// Bulk "insert, or replace if already present, preserving id/timestamps"
/// — the local-store half of `ZenithSync.PostgresImporter`'s one-time
/// Postgres → SQLite copy. Lives in `ZenithData` (not `ZenithSync`) so the
/// GRDB specifics stay next to the schema they write into; `ZenithSync`
/// only decodes Postgres rows into these same model types and hands them
/// here. Idempotent by `id`, so re-running an import merges rather than
/// duplicating.
public enum LocalImport {
    public struct IssueRepoLink: Sendable {
        public let id: UUID
        public let issueId: UUID
        public let repoId: UUID

        public init(id: UUID, issueId: UUID, repoId: UUID) {
            self.id = id
            self.issueId = issueId
            self.repoId = repoId
        }
    }

    public static func apply(
        to db: ZenithDatabase,
        spaces: [Space],
        spaceImages: [SpaceImage],
        milestones: [Milestone],
        repos: [Repo],
        customFields: [CustomField],
        views: [ZView],
        issues: [Issue],
        issueRepoLinks: [IssueRepoLink]
    ) async throws {
        let importedAt = Date()
        try await db.write { d in
            // Rows within a table can reference each other out of order
            // (e.g. `issues.parent_id` self-references) — deferring FK
            // checks to end-of-transaction avoids ordering this batch
            // topologically within each table, only across tables.
            try d.execute(sql: "PRAGMA defer_foreign_keys = ON")

            for space in spaces { try upsert(d, space) }
            for image in spaceImages { try upsert(d, image) }
            for milestone in milestones { try upsert(d, milestone) }
            for repo in repos { try upsert(d, repo) }
            for field in customFields { try upsert(d, field) }
            for view in views { try upsert(d, view) }
            for issue in issues { try upsert(d, issue) }
            for link in issueRepoLinks { try upsert(d, link, importedAt: importedAt) }
        }
    }

    private static func upsert(_ d: Database, _ space: Space) throws {
        try d.execute(
            sql: """
                INSERT INTO spaces (id, name, slug, description, context, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  name = excluded.name, slug = excluded.slug, description = excluded.description,
                  context = excluded.context, created_at = excluded.created_at, updated_at = excluded.updated_at
                """,
            arguments: [
                space.id.databaseText, space.name, space.slug, space.description, space.context,
                space.createdAt, space.updatedAt,
            ]
        )
    }

    private static func upsert(_ d: Database, _ image: SpaceImage) throws {
        // Postgres `space_images` has no `updated_at` column — `created_at`
        // stands in for it here, same as the app's own writes.
        try d.execute(
            sql: """
                INSERT INTO space_images (id, space_id, data_url, label, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  space_id = excluded.space_id, data_url = excluded.data_url, label = excluded.label,
                  created_at = excluded.created_at, updated_at = excluded.updated_at
                """,
            arguments: [image.id.databaseText, image.spaceId.databaseText, image.dataUrl, image.label, image.createdAt, image.createdAt]
        )
    }

    private static func upsert(_ d: Database, _ milestone: Milestone) throws {
        try d.execute(
            sql: """
                INSERT INTO milestones (id, space_id, title, description, due_date, status, closed_at, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  space_id = excluded.space_id, title = excluded.title, description = excluded.description,
                  due_date = excluded.due_date, status = excluded.status, closed_at = excluded.closed_at,
                  created_at = excluded.created_at, updated_at = excluded.updated_at
                """,
            arguments: [
                milestone.id.databaseText, milestone.spaceId.databaseText, milestone.title, milestone.description,
                milestone.dueDate, milestone.status, milestone.closedAt, milestone.createdAt, milestone.updatedAt,
            ]
        )
    }

    private static func upsert(_ d: Database, _ repo: Repo) throws {
        try d.execute(
            sql: """
                INSERT INTO repos (id, space_id, name, url, cached_context, cached_at, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  space_id = excluded.space_id, name = excluded.name, url = excluded.url,
                  cached_context = excluded.cached_context, cached_at = excluded.cached_at,
                  created_at = excluded.created_at, updated_at = excluded.updated_at
                """,
            arguments: [
                repo.id.databaseText, repo.spaceId.databaseText, repo.name, repo.url, repo.cachedContext,
                repo.cachedAt, repo.createdAt, repo.updatedAt,
            ]
        )
    }

    private static func upsert(_ d: Database, _ field: CustomField) throws {
        try d.execute(
            sql: """
                INSERT INTO custom_fields (id, space_id, key, name, type, options, position, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  space_id = excluded.space_id, key = excluded.key, name = excluded.name, type = excluded.type,
                  options = excluded.options, position = excluded.position, created_at = excluded.created_at,
                  updated_at = excluded.updated_at
                """,
            arguments: [
                field.id.databaseText, field.spaceId.databaseText, field.key, field.name, field.type.rawValue,
                try field.options.jsonText(), field.position, field.createdAt, field.updatedAt,
            ]
        )
    }

    private static func upsert(_ d: Database, _ view: ZView) throws {
        try d.execute(
            sql: """
                INSERT INTO views (id, space_id, name, type, position, is_default, config, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  space_id = excluded.space_id, name = excluded.name, type = excluded.type,
                  position = excluded.position, is_default = excluded.is_default, config = excluded.config,
                  created_at = excluded.created_at, updated_at = excluded.updated_at
                """,
            arguments: [
                view.id.databaseText, view.spaceId.databaseText, view.name, view.type.rawValue, view.position,
                view.isDefault, try view.config.jsonText(), view.createdAt, view.updatedAt,
            ]
        )
    }

    private static func upsert(_ d: Database, _ issue: Issue) throws {
        try d.execute(
            sql: """
                INSERT INTO issues (
                    id, space_id, milestone_id, parent_id, title, description, status, is_closed, priority,
                    tags, branch, estimate, due_date, start_date, custom_field_values, position, closed_at,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  space_id = excluded.space_id, milestone_id = excluded.milestone_id, parent_id = excluded.parent_id,
                  title = excluded.title, description = excluded.description, status = excluded.status,
                  is_closed = excluded.is_closed, priority = excluded.priority, tags = excluded.tags,
                  branch = excluded.branch, estimate = excluded.estimate, due_date = excluded.due_date,
                  start_date = excluded.start_date, custom_field_values = excluded.custom_field_values,
                  position = excluded.position, closed_at = excluded.closed_at, created_at = excluded.created_at,
                  updated_at = excluded.updated_at
                """,
            arguments: [
                issue.id.databaseText, issue.spaceId.databaseText, issue.milestoneId?.databaseText, issue.parentId?.databaseText,
                issue.title, issue.description, issue.status.rawValue, issue.isClosed, issue.priority.rawValue,
                try JSONColumn.encodeStringArray(issue.tags), issue.branch, issue.estimate, issue.dueDate, issue.startDate,
                try JSONColumn.encodeMap(issue.customFieldValues), issue.position, issue.closedAt, issue.createdAt, issue.updatedAt,
            ]
        )
    }

    /// Preserves Postgres's own `id` for the link (not a fresh local one) —
    /// otherwise a later sync pull of the same, unchanged link would carry
    /// Postgres's original `id`, which wouldn't match this row's `id` and
    /// would collide with the `(issue_id, repo_id)` uniqueness constraint
    /// instead of being recognized as the same row. `ON CONFLICT(issue_id,
    /// repo_id)` (not `id`) for the same reason: re-running an import must
    /// recognize an existing link by its natural key even if some earlier,
    /// pre-fix import left a stale local `id` behind.
    private static func upsert(_ d: Database, _ link: IssueRepoLink, importedAt: Date) throws {
        try d.execute(
            sql: """
                INSERT INTO issue_repos (id, issue_id, repo_id, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(issue_id, repo_id) DO UPDATE SET id = excluded.id, updated_at = excluded.updated_at
                """,
            arguments: [link.id.databaseText, link.issueId.databaseText, link.repoId.databaseText, importedAt]
        )
    }
}
