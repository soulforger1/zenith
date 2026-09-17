import Foundation
import ZenithData

/// Drives one bidirectional sync round against a single `SyncTarget`:
/// pull remote changes since the last successful pull and apply them
/// locally (last-write-wins, via `LocalSyncStore`), then push local
/// changes since the last successful push. Both directions are best-effort
/// per row — one bad row doesn't roll back the rest of the round (mirrors
/// `LocalSyncStore.applyUpsert`/`applyDelete`, which are themselves
/// per-row transactions, not one big transaction for the whole round).
public enum SyncReconciler {
    public static func runRound(store: ZenithDatabase, target: SyncTarget) async throws -> SyncOutcome {
        let roundStart = Date()
        var state = try await LocalSyncStore.loadSyncState(store, target: target.id)

        do {
            let remote = try await target.fetchRemoteDelta(since: state.lastPulledAt ?? .distantPast)

            var pulled = 0
            for row in remote.upserts.sorted(by: { $0.table.dependencyIndex < $1.table.dependencyIndex }) {
                try await LocalSyncStore.applyUpsert(store, row)
                pulled += 1
            }
            // Deletes run in reverse dependency order (children before
            // parents) so a cascade-eligible row is never left dangling.
            for tombstone in remote.deletes.sorted(by: { $0.table.dependencyIndex > $1.table.dependencyIndex }) {
                try await LocalSyncStore.applyDelete(store, table: tombstone.table, id: tombstone.id, deletedAt: tombstone.deletedAt)
                pulled += 1
            }

            let local = try await LocalSyncStore.localDelta(store, since: state.lastPushedAt ?? .distantPast)
            try await target.pushLocalDelta(local)

            // Cursors advance to *round start*, not completion — anything
            // written locally or remotely during the round is simply
            // re-processed (harmlessly, idempotently) next round.
            state.lastPulledAt = roundStart
            state.lastPushedAt = roundStart
            state.lastSuccessAt = Date()
            state.lastError = nil
            try await LocalSyncStore.saveSyncState(store, state)

            return SyncOutcome(pulled: pulled, pushed: local.upserts.count + local.deletes.count)
        } catch {
            state.lastError = error.diagnosticDescription
            try? await LocalSyncStore.saveSyncState(store, state)
            throw error
        }
    }
}
