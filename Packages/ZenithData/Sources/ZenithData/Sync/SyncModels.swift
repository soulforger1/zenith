import Foundation

/// A full-row snapshot for one synced table, in the generic column shape
/// both `LocalSyncStore` (reading/writing SQLite) and a remote
/// `SyncTarget` (reading/writing Postgres, or eventually a synced folder)
/// can produce and consume without either depending on the other's storage
/// details. `columns` always holds every column of `table` — sync applies
/// whole-row last-write-wins, never a partial patch.
public struct SyncRow: Sendable, Equatable {
    public let table: SyncTable
    /// The row's `id`, as lowercased text (matches `UUID.databaseText`).
    public let id: String
    public let updatedAt: Date
    public let columns: [String: SyncValue]

    public init(table: SyncTable, id: String, updatedAt: Date, columns: [String: SyncValue]) {
        self.table = table
        self.id = id
        self.updatedAt = updatedAt
        self.columns = columns
    }
}

/// Records that a row was deleted, since a plain `DELETE` leaves no trace
/// for a sync target to notice on its next pull.
public struct SyncTombstone: Sendable, Equatable {
    public let table: SyncTable
    public let id: String
    public let deletedAt: Date

    public init(table: SyncTable, id: String, deletedAt: Date) {
        self.table = table
        self.id = id
        self.deletedAt = deletedAt
    }
}

/// One direction's worth of changes — used both for "what changed locally
/// since we last pushed" (`LocalSyncStore.localDelta`) and "what changed
/// remotely since we last pulled" (a `SyncTarget`'s `fetchRemoteDelta`).
public struct SyncDelta: Sendable, Equatable {
    public var upserts: [SyncRow]
    public var deletes: [SyncTombstone]

    public init(upserts: [SyncRow] = [], deletes: [SyncTombstone] = []) {
        self.upserts = upserts
        self.deletes = deletes
    }
}

/// Per-target sync bookkeeping, persisted in the local `sync_state` table.
/// `target` is an opaque id (`"postgres"`, `"icloud"`, ...) — one row per
/// configured sync target.
public struct SyncStateRecord: Sendable, Equatable {
    public var target: String
    public var lastPulledAt: Date?
    public var lastPushedAt: Date?
    public var lastSuccessAt: Date?
    public var lastError: String?
    /// Opaque, target-specific continuation token — unused by
    /// `PostgresSyncTarget` (a plain timestamp cursor is enough for a SQL
    /// `WHERE updated_at > ?`); reserved for a folder-based target that
    /// needs to remember per-file state.
    public var cursor: String?

    public init(
        target: String, lastPulledAt: Date? = nil, lastPushedAt: Date? = nil,
        lastSuccessAt: Date? = nil, lastError: String? = nil, cursor: String? = nil
    ) {
        self.target = target
        self.lastPulledAt = lastPulledAt
        self.lastPushedAt = lastPushedAt
        self.lastSuccessAt = lastSuccessAt
        self.lastError = lastError
        self.cursor = cursor
    }
}
