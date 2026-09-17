import Foundation
import ZenithData

/// A remote (or remote-ish — a synced folder counts too) place the local
/// store can reconcile with. `SyncReconciler` drives every conformance the
/// same way: pull whatever changed since the last successful round, apply
/// it locally with last-write-wins, then push whatever changed locally
/// since the last successful push.
public protocol SyncTarget: Sendable {
    /// Stable id used as the `sync_state.target` key — `"postgres"` for
    /// `PostgresSyncTarget`, `"icloud"` for the folder target (Phase 3).
    var id: String { get }

    /// Every remote row/tombstone changed strictly after `since`.
    func fetchRemoteDelta(since: Date) async throws -> SyncDelta

    /// Applies local changes to the remote. Must be safe to call with a
    /// delta the remote has already seen (e.g. after a crash mid-round) —
    /// implementations enforce their own last-write-wins guard server-side
    /// (`PostgresSyncTarget` does this with a conditional `ON CONFLICT`).
    func pushLocalDelta(_ delta: SyncDelta) async throws
}
