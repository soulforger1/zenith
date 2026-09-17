import Foundation
import PostgresNIO
import ZenithData

/// The Postgres sync target — periodic bidirectional reconciliation with a
/// remote Postgres database (the same one `PostgresImporter` can do a
/// one-time copy from). Requires the `0007_sync_tombstones` migration
/// (`db/migrations/`) to already be applied to that database.
///
/// Every synced table gets a typed SELECT for the pull side (matching
/// `Database/Schema/Migrations.swift`'s local schema 1:1) and a generic,
/// last-write-wins `INSERT ... ON CONFLICT ... WHERE excluded.updated_at >
/// ...` upsert for the push side — the same shape
/// `ZenithData.LocalSyncStore.applyUpsert` uses locally, mirrored
/// server-side so either direction converges under concurrent edits.
public struct PostgresSyncTarget: SyncTarget {
    public let id = "postgres"
    private let connectionString: String

    public init(connectionString: String) {
        self.connectionString = connectionString
    }

    /// Mirrors `ZenithData.LocalSyncStore`'s conflict target choice:
    /// `issue_repos` has a natural-key uniqueness constraint on
    /// `(issue_id, repo_id)` (`issue_repos_issue_id_repo_id_idx`) alongside
    /// its surrogate `id` — conflict on the natural key so two
    /// independently-`id`'d copies of the same link (e.g. one from a
    /// one-time import, one from a later sync) merge instead of colliding.
    private static func conflictTarget(for table: SyncTable) -> String {
        table == .issueRepos ? "issue_id, repo_id" : "id"
    }

    public func fetchRemoteDelta(since: Date) async throws -> SyncDelta {
        let gateway = try PostgresGateway(connectionString: connectionString)
        await gateway.start()
        do {
            var upserts: [SyncRow] = []
            for table in SyncTable.dependencyOrder {
                upserts += try await fetchTable(gateway, table: table, since: since)
            }
            let deletes = try await fetchTombstones(gateway, since: since)
            await gateway.shutdown()
            return SyncDelta(upserts: upserts, deletes: deletes)
        } catch {
            await gateway.shutdown()
            throw error
        }
    }

    public func pushLocalDelta(_ delta: SyncDelta) async throws {
        let gateway = try PostgresGateway(connectionString: connectionString)
        await gateway.start()
        do {
            for row in delta.upserts.sorted(by: { $0.table.dependencyIndex < $1.table.dependencyIndex }) {
                try await pushUpsert(gateway, row)
            }
            for tombstone in delta.deletes.sorted(by: { $0.table.dependencyIndex > $1.table.dependencyIndex }) {
                try await pushDelete(gateway, tombstone)
            }
            await gateway.shutdown()
        } catch {
            await gateway.shutdown()
            throw error
        }
    }

    // MARK: - Pull

    /// Column lists mirror `ZenithSync.PostgresRowMapping`'s (the Phase-1
    /// importer's typed mapping) — same `::text` casts on `due_date`/
    /// `start_date` for the same reason.
    private static let selectColumns: [SyncTable: String] = [
        .spaces: "id, name, slug, description, context, created_at, updated_at",
        .spaceImages: "id, space_id, data_url, label, created_at, updated_at",
        .milestones: """
            id, space_id, title, description, due_date::text AS due_date, status, closed_at, created_at, updated_at
            """,
        .repos: "id, space_id, name, url, cached_context, cached_at, created_at, updated_at",
        .customFields: "id, space_id, key, name, type, options, position, created_at, updated_at",
        .views: "id, space_id, name, type, position, is_default, config, created_at, updated_at",
        .issues: """
            id, space_id, milestone_id, parent_id, title, description, status, is_closed, priority, tags, branch,
            estimate, due_date::text AS due_date, start_date::text AS start_date, custom_field_values, position,
            closed_at, created_at, updated_at
            """,
        .issueRepos: "id, issue_id, repo_id, updated_at",
    ]

    private func fetchTable(_ gateway: PostgresGateway, table: SyncTable, since: Date) async throws -> [SyncRow] {
        let columns = Self.selectColumns[table] ?? "*"
        var bindings = PostgresBindings()
        bindings.append(since)
        let rows = try await gateway.query(
            PostgresQuery(unsafeSQL: "SELECT \(columns) FROM \(table.rawValue) WHERE updated_at > $1", binds: bindings)
        )
        var results: [SyncRow] = []
        for try await row in rows { results.append(try PostgresSyncRowMapping.syncRow(table, row)) }
        return results
    }

    private func fetchTombstones(_ gateway: PostgresGateway, since: Date) async throws -> [SyncTombstone] {
        var bindings = PostgresBindings()
        bindings.append(since)
        let rows = try await gateway.query(
            PostgresQuery(unsafeSQL: "SELECT table_name, row_id, deleted_at FROM sync_tombstones WHERE deleted_at > $1", binds: bindings)
        )
        var results: [SyncTombstone] = []
        for try await row in rows {
            let r = row.makeRandomAccess()
            guard let tableName = try r["table_name"].decode(String?.self), let table = SyncTable(rawValue: tableName) else { continue }
            let rowId = try r["row_id"].decode(UUID.self)
            let deletedAt = try r["deleted_at"].decode(Date.self)
            results.append(SyncTombstone(table: table, id: rowId.uuidString.lowercased(), deletedAt: deletedAt))
        }
        return results
    }

    // MARK: - Push

    /// Upserts one row, guarded both ways: skipped entirely if the remote
    /// already recorded a tombstone at least as new as `row` (a remote
    /// delete beats a stale local echo of the old row), and — via the
    /// `WHERE excluded.updated_at > ...` on the `ON CONFLICT` — a no-op if
    /// the remote's own copy is already newer.
    private func pushUpsert(_ gateway: PostgresGateway, _ row: SyncRow) async throws {
        guard let rowId = UUID(uuidString: row.id) else { return }

        var tombstoneBindings = PostgresBindings()
        tombstoneBindings.append(row.table.rawValue)
        tombstoneBindings.append(rowId)
        let tombstoneRows = try await gateway.query(
            PostgresQuery(unsafeSQL: "SELECT deleted_at FROM sync_tombstones WHERE table_name = $1 AND row_id = $2", binds: tombstoneBindings)
        )
        for try await tombstoneRow in tombstoneRows {
            let deletedAt = try tombstoneRow.makeRandomAccess()["deleted_at"].decode(Date.self)
            if deletedAt >= row.updatedAt { return }
        }

        var bindings = PostgresBindings()
        var names: [String] = []
        var placeholders: [String] = []
        var updateAssignments: [String] = []
        for name in row.columns.keys.sorted() {
            let fragment = try PostgresRowBinding.fragment(column: name, value: row.columns[name]!, appendingTo: &bindings)
            names.append(name)
            placeholders.append(fragment)
            updateAssignments.append("\(name) = excluded.\(name)")
        }
        let sql = """
            INSERT INTO \(row.table.rawValue) (\(names.joined(separator: ", ")))
            VALUES (\(placeholders.joined(separator: ", ")))
            ON CONFLICT (\(Self.conflictTarget(for: row.table))) DO UPDATE SET \(updateAssignments.joined(separator: ", "))
            WHERE excluded.updated_at > \(row.table.rawValue).updated_at
            """
        try await gateway.execute(PostgresQuery(unsafeSQL: sql, binds: bindings))

        var clearBindings = PostgresBindings()
        clearBindings.append(row.table.rawValue)
        clearBindings.append(rowId)
        try await gateway.execute(
            PostgresQuery(unsafeSQL: "DELETE FROM sync_tombstones WHERE table_name = $1 AND row_id = $2", binds: clearBindings)
        )
    }

    /// Records/refreshes the remote tombstone (`GREATEST` so an older echo
    /// never regresses a newer delete already recorded there), then
    /// deletes the row if it's still present and older than the delete —
    /// a newer remote edit beats an older local delete.
    private func pushDelete(_ gateway: PostgresGateway, _ tombstone: SyncTombstone) async throws {
        guard let rowId = UUID(uuidString: tombstone.id) else { return }

        var tombstoneBindings = PostgresBindings()
        tombstoneBindings.append(tombstone.table.rawValue)
        tombstoneBindings.append(rowId)
        tombstoneBindings.append(tombstone.deletedAt)
        try await gateway.execute(
            PostgresQuery(
                unsafeSQL: """
                    INSERT INTO sync_tombstones (table_name, row_id, deleted_at) VALUES ($1, $2, $3)
                    ON CONFLICT (table_name, row_id) DO UPDATE SET deleted_at = GREATEST(sync_tombstones.deleted_at, excluded.deleted_at)
                    """,
                binds: tombstoneBindings
            )
        )

        var deleteBindings = PostgresBindings()
        deleteBindings.append(rowId)
        deleteBindings.append(tombstone.deletedAt)
        try await gateway.execute(
            PostgresQuery(unsafeSQL: "DELETE FROM \(tombstone.table.rawValue) WHERE id = $1 AND updated_at < $2", binds: deleteBindings)
        )
    }
}
