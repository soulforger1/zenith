import Foundation
import PostgresNIO
import ZenithData

/// One-time copy of an existing Postgres database into the local SQLite
/// store — the migration path for anyone upgrading from the pre-local-first
/// app (which talked to Postgres directly). Preserves every row's `id`,
/// `created_at`, `updated_at`, so history, custom-field references, and
/// cross-links survive the move. Safe to re-run: `LocalImport.apply` upserts
/// by id.
public enum PostgresImporter {
    public struct Report: Sendable, Equatable {
        public var spaces = 0
        public var spaceImages = 0
        public var milestones = 0
        public var repos = 0
        public var customFields = 0
        public var views = 0
        public var issues = 0
        public var issueRepoLinks = 0
    }

    public static func run(connectionString: String, into store: ZenithDatabase) async throws -> Report {
        let gateway = try PostgresGateway(connectionString: connectionString)
        await gateway.start()
        do {
            try await gateway.ping()
            let report = try await importAll(gateway, into: store)
            await gateway.shutdown()
            return report
        } catch {
            await gateway.shutdown()
            throw error
        }
    }

    private static func importAll(_ gateway: PostgresGateway, into store: ZenithDatabase) async throws -> Report {
        // Fetched in FK-dependency order, matching the order `LocalImport`
        // writes them in.
        let spaces = try await fetchAll(
            gateway, sql: "SELECT id, name, slug, description, context, created_at, updated_at FROM spaces",
            map: PostgresRowMapping.space
        )
        let spaceImages = try await fetchAll(
            gateway, sql: "SELECT id, space_id, data_url, label, created_at FROM space_images",
            map: PostgresRowMapping.spaceImage
        )
        let milestones = try await fetchAll(
            gateway,
            sql: """
                SELECT id, space_id, title, description, due_date::text AS due_date, status, closed_at, created_at, updated_at
                FROM milestones
                """,
            map: PostgresRowMapping.milestone
        )
        let repos = try await fetchAll(
            gateway, sql: "SELECT id, space_id, name, url, cached_context, cached_at, created_at, updated_at FROM repos",
            map: PostgresRowMapping.repo
        )
        let customFields = try await fetchAll(
            gateway, sql: "SELECT id, space_id, key, name, type, options, position, created_at, updated_at FROM custom_fields",
            map: PostgresRowMapping.customField
        )
        let views = try await fetchAll(
            gateway, sql: "SELECT id, space_id, name, type, position, is_default, config, created_at, updated_at FROM views",
            map: PostgresRowMapping.view
        )
        let issues = try await fetchAll(
            gateway,
            sql: """
                SELECT id, space_id, milestone_id, parent_id, title, description, status, is_closed, priority,
                       tags, branch, estimate, due_date::text AS due_date, start_date::text AS start_date,
                       custom_field_values, position, closed_at, created_at, updated_at
                FROM issues
                """,
            map: PostgresRowMapping.issue
        )
        let issueRepoLinks = try await fetchAll(
            gateway, sql: "SELECT id, issue_id, repo_id FROM issue_repos", map: PostgresRowMapping.issueRepoLink
        )

        try await LocalImport.apply(
            to: store, spaces: spaces, spaceImages: spaceImages, milestones: milestones, repos: repos,
            customFields: customFields, views: views, issues: issues, issueRepoLinks: issueRepoLinks
        )

        return Report(
            spaces: spaces.count, spaceImages: spaceImages.count, milestones: milestones.count, repos: repos.count,
            customFields: customFields.count, views: views.count, issues: issues.count, issueRepoLinks: issueRepoLinks.count
        )
    }

    private static func fetchAll<T: Sendable>(
        _ gateway: PostgresGateway, sql: String, map: @Sendable (PostgresRow) throws -> T
    ) async throws -> [T] {
        var results: [T] = []
        let rows = try await gateway.query(PostgresQuery(unsafeSQL: sql))
        for try await row in rows { results.append(try map(row)) }
        return results
    }
}
