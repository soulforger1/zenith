import Foundation
import GRDB

/// Generic (schema-agnostic) local-store access for the sync layer —
/// separate from `Queries/` (which is model-typed, and derives values like
/// fractional positions and slugs that only make sense for a locally
/// *originated* write) because sync applies whole remote rows verbatim and
/// needs to read/write *any* synced table uniformly. `ZenithSync`'s
/// `SyncReconciler` and remote `SyncTarget`s are the only callers.
public enum LocalSyncStore {
    /// Every table's rows are conflict-resolved by their surrogate `id` —
    /// except `issue_repos`, which also carries a natural-key uniqueness
    /// constraint on `(issue_id, repo_id)`. Two independently-created
    /// copies of "the same link" (e.g. one imported from Postgres with a
    /// freshly-generated local `id`, one arriving later from a sync pull
    /// with Postgres's original `id`) would otherwise collide on that
    /// constraint instead of being recognized as the same row — conflict
    /// on the natural key for this one table so they merge instead.
    private static func conflictTarget(for table: SyncTable) -> String {
        table == .issueRepos ? "issue_id, repo_id" : "id"
    }

    // MARK: - Reading local changes to push

    /// Rows in `table` whose `updated_at` is strictly after `since` —
    /// candidates to push to a sync target. No separate dirty flag is
    /// tracked: every mutation in `Queries/` already stamps `updated_at`,
    /// so this column *is* the change log.
    public static func dirtyRows(_ db: ZenithDatabase, table: SyncTable, since: Date) async throws -> [SyncRow] {
        try await db.read { d in
            let rows = try Row.fetchAll(
                d, sql: "SELECT * FROM \(table.rawValue) WHERE updated_at > ?", arguments: [DBDate.string(since)]
            )
            return try rows.map { try syncRow(table, $0) }
        }
    }

    /// Every tombstone (any table) recorded after `since`.
    public static func tombstones(_ db: ZenithDatabase, since: Date) async throws -> [SyncTombstone] {
        try await db.read { d in
            let rows = try Row.fetchAll(
                d, sql: "SELECT table_name, row_id, deleted_at FROM sync_tombstones WHERE deleted_at > ?",
                arguments: [DBDate.string(since)]
            )
            return rows.compactMap { row -> SyncTombstone? in
                guard let tableName: String = row["table_name"], let table = SyncTable(rawValue: tableName),
                    let rowId: String = row["row_id"], let deletedAtText: String = row["deleted_at"],
                    let deletedAt = DBDate.parse(deletedAtText)
                else { return nil }
                return SyncTombstone(table: table, id: rowId, deletedAt: deletedAt)
            }
        }
    }

    /// Every local change (every table's dirty rows + every tombstone)
    /// since `since`, in dependency order — what a sync target's push step
    /// sends in one round.
    public static func localDelta(_ db: ZenithDatabase, since: Date) async throws -> SyncDelta {
        var upserts: [SyncRow] = []
        for table in SyncTable.dependencyOrder {
            upserts += try await dirtyRows(db, table: table, since: since)
        }
        return SyncDelta(upserts: upserts, deletes: try await tombstones(db, since: since))
    }

    private static func syncRow(_ table: SyncTable, _ row: Row) throws -> SyncRow {
        guard let id: String = row["id"] else {
            throw StoreError.malformedRow("\(table.rawValue) row missing id")
        }
        guard let updatedAtText: String = row["updated_at"], let updatedAt = DBDate.parse(updatedAtText) else {
            throw StoreError.malformedRow("\(table.rawValue) row \(id) has a missing/unparseable updated_at")
        }
        var columns: [String: SyncValue] = [:]
        for (name, dbValue) in row {
            columns[name] = SyncValue.fromDatabaseValue(dbValue) ?? .null
        }
        return SyncRow(table: table, id: id, updatedAt: updatedAt, columns: columns)
    }

    // MARK: - Applying remote changes

    /// Applies a remote row as a last-write-wins upsert.
    ///
    /// - If this id was deleted locally *more recently* than `row.updatedAt`,
    ///   the local delete wins and nothing happens (no resurrection).
    /// - Otherwise, inserts if absent, or replaces if `row.updatedAt` is
    ///   strictly newer than the existing local row (a no-op otherwise,
    ///   enforced by the `WHERE` on the upsert's conflict action so this
    ///   never errors) — and clears any (now-stale) local tombstone for
    ///   this id, since the row exists again.
    public static func applyUpsert(_ db: ZenithDatabase, _ row: SyncRow) async throws {
        try await db.write { d in
            if let tombstoneText: String = try String.fetchOne(
                d, sql: "SELECT deleted_at FROM sync_tombstones WHERE table_name = ? AND row_id = ?",
                arguments: [row.table.rawValue, row.id]
            ), let tombstoneAt = DBDate.parse(tombstoneText), tombstoneAt >= row.updatedAt {
                return
            }

            var names: [String] = []
            var placeholders: [String] = []
            var updateAssignments: [String] = []
            var arguments: [SyncValue] = []
            for (name, value) in row.columns {
                names.append(name)
                placeholders.append("?")
                updateAssignments.append("\(name) = excluded.\(name)")
                arguments.append(value)
            }

            let sql = """
                INSERT INTO \(row.table.rawValue) (\(names.joined(separator: ", ")))
                VALUES (\(placeholders.joined(separator: ", ")))
                ON CONFLICT(\(conflictTarget(for: row.table))) DO UPDATE SET \(updateAssignments.joined(separator: ", "))
                WHERE excluded.updated_at > \(row.table.rawValue).updated_at
                """
            try d.execute(sql: sql, arguments: StatementArguments(arguments))
            try d.execute(
                sql: "DELETE FROM sync_tombstones WHERE table_name = ? AND row_id = ?",
                arguments: [row.table.rawValue, row.id]
            )
        }
    }

    /// Applies a remote delete as a last-write-wins delete: only deletes if
    /// the local row's `updated_at` is older than `deletedAt` (a newer
    /// local edit beats an older remote delete). The table's `AFTER
    /// DELETE` trigger records a local tombstone whenever a row is
    /// actually removed, so this is safe to call redundantly.
    public static func applyDelete(_ db: ZenithDatabase, table: SyncTable, id: String, deletedAt: Date) async throws {
        try await db.write { d in
            try d.execute(
                sql: "DELETE FROM \(table.rawValue) WHERE id = ? AND updated_at < ?",
                arguments: [id, DBDate.string(deletedAt)]
            )
        }
    }

    // MARK: - Sync state

    public static func loadSyncState(_ db: ZenithDatabase, target: String) async throws -> SyncStateRecord {
        try await db.read { d in
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM sync_state WHERE target = ?", arguments: [target]) else {
                return SyncStateRecord(target: target)
            }
            return SyncStateRecord(
                target: target,
                lastPulledAt: (row["last_pulled_at"] as String?).flatMap(DBDate.parse),
                lastPushedAt: (row["last_pushed_at"] as String?).flatMap(DBDate.parse),
                lastSuccessAt: (row["last_success_at"] as String?).flatMap(DBDate.parse),
                lastError: row["last_error"],
                cursor: row["cursor"]
            )
        }
    }

    public static func saveSyncState(_ db: ZenithDatabase, _ state: SyncStateRecord) async throws {
        try await db.write { d in
            try d.execute(
                sql: """
                    INSERT INTO sync_state (target, last_pulled_at, last_pushed_at, last_success_at, last_error, cursor)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(target) DO UPDATE SET
                      last_pulled_at = excluded.last_pulled_at, last_pushed_at = excluded.last_pushed_at,
                      last_success_at = excluded.last_success_at, last_error = excluded.last_error,
                      cursor = excluded.cursor
                    """,
                arguments: [
                    state.target, state.lastPulledAt.map(DBDate.string), state.lastPushedAt.map(DBDate.string),
                    state.lastSuccessAt.map(DBDate.string), state.lastError, state.cursor,
                ]
            )
        }
    }
}
