import Foundation
import ZenithData

@testable import ZenithSync

/// An in-memory `SyncTarget` for exercising `SyncReconciler` without a real
/// database — applies the same server-side last-write-wins guard
/// `PostgresSyncTarget` enforces in SQL, so reconciler tests cover the same
/// convergence behavior a real target would.
actor MockSyncTarget: SyncTarget {
    nonisolated let id: String
    private var remoteRows: [String: SyncRow] = [:]
    private var remoteTombstones: [String: SyncTombstone] = [:]
    private(set) var pushedUpserts: [SyncRow] = []
    private(set) var pushedDeletes: [SyncTombstone] = []
    private var fetchError: (any Error)?
    private var pushError: (any Error)?

    init(id: String = "mock") {
        self.id = id
    }

    private static func key(_ table: SyncTable, _ id: String) -> String { "\(table.rawValue):\(id)" }

    func seedRemote(_ row: SyncRow) {
        remoteRows[Self.key(row.table, row.id)] = row
    }

    func seedRemoteTombstone(_ tombstone: SyncTombstone) {
        remoteTombstones[Self.key(tombstone.table, tombstone.id)] = tombstone
    }

    func remoteRow(_ table: SyncTable, _ id: String) -> SyncRow? {
        remoteRows[Self.key(table, id)]
    }

    func setFetchError(_ error: (any Error)?) {
        fetchError = error
    }

    func setPushError(_ error: (any Error)?) {
        pushError = error
    }

    func fetchRemoteDelta(since: Date) async throws -> SyncDelta {
        if let fetchError { throw fetchError }
        return SyncDelta(
            upserts: remoteRows.values.filter { $0.updatedAt > since },
            deletes: remoteTombstones.values.filter { $0.deletedAt > since }
        )
    }

    func pushLocalDelta(_ delta: SyncDelta) async throws {
        if let pushError { throw pushError }
        for row in delta.upserts {
            let key = Self.key(row.table, row.id)
            if let existing = remoteRows[key], existing.updatedAt >= row.updatedAt { continue }
            remoteRows[key] = row
            pushedUpserts.append(row)
        }
        for tombstone in delta.deletes {
            let key = Self.key(tombstone.table, tombstone.id)
            if let existingRow = remoteRows[key], existingRow.updatedAt >= tombstone.deletedAt { continue }
            remoteRows.removeValue(forKey: key)
            remoteTombstones[key] = tombstone
            pushedDeletes.append(tombstone)
        }
    }
}

struct MockSyncError: Error, CustomStringConvertible {
    let description: String
}
