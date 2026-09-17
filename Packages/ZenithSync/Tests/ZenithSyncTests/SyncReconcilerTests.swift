import Foundation
import Testing
import ZenithData

@testable import ZenithSync

@Suite("SyncReconciler")
struct SyncReconcilerTests {
    private func spaceRow(id: UUID = UUID(), name: String = "Remote Space", updatedAt: Date) -> SyncRow {
        SyncRow(
            table: .spaces, id: id.uuidString.lowercased(), updatedAt: updatedAt,
            columns: [
                "id": .text(id.uuidString.lowercased()), "name": .text(name), "slug": .text(name.lowercased()),
                "description": .null, "context": .null,
                "created_at": .date(updatedAt), "updated_at": .date(updatedAt),
            ]
        )
    }

    @Test("a local-only change is pushed to the target")
    func pushesLocalChanges() async throws {
        let store = try ZenithDatabase.inMemory()
        let target = MockSyncTarget()
        let space = try await SpaceQueries.createSpace(store, name: "Local Space", description: nil)

        let outcome = try await SyncReconciler.runRound(store: store, target: target)

        #expect(outcome.pushed >= 1)
        let remote = await target.remoteRow(.spaces, space.id.uuidString.lowercased())
        #expect(remote?.columns["name"] == .text("Local Space"))
    }

    @Test("a remote-only change is pulled into the local store")
    func pullsRemoteChanges() async throws {
        let store = try ZenithDatabase.inMemory()
        let target = MockSyncTarget()
        let id = UUID()
        await target.seedRemote(spaceRow(id: id, name: "From Remote", updatedAt: Date()))

        let outcome = try await SyncReconciler.runRound(store: store, target: target)

        #expect(outcome.pulled == 1)
        #expect(try await SpaceQueries.getSpaceById(store, id: id)?.name == "From Remote")
    }

    @Test("concurrent edits converge on the newer timestamp in both directions")
    func concurrentEditsConverge() async throws {
        let store = try ZenithDatabase.inMemory()
        let target = MockSyncTarget()

        // Local is newer -> local wins, and the remote gets updated to match.
        let newerLocal = try await SpaceQueries.createSpace(store, name: "Local Wins", description: nil)
        await target.seedRemote(spaceRow(id: newerLocal.id, name: "Stale Remote", updatedAt: newerLocal.updatedAt.addingTimeInterval(-3600)))

        // Remote is newer -> remote wins, local gets overwritten.
        let staleLocalId = UUID()
        try await LocalSyncStore.applyUpsert(store, spaceRow(id: staleLocalId, name: "Stale Local", updatedAt: Date().addingTimeInterval(-3600)))
        await target.seedRemote(spaceRow(id: staleLocalId, name: "Remote Wins", updatedAt: Date()))

        _ = try await SyncReconciler.runRound(store: store, target: target)

        #expect(try await SpaceQueries.getSpaceById(store, id: newerLocal.id)?.name == "Local Wins")
        let remoteAfterPush = await target.remoteRow(.spaces, newerLocal.id.uuidString.lowercased())
        #expect(remoteAfterPush?.columns["name"] == .text("Local Wins"))

        #expect(try await SpaceQueries.getSpaceById(store, id: staleLocalId)?.name == "Remote Wins")
    }

    @Test("a local delete after the last push is propagated to the target")
    func propagatesLocalDeletes() async throws {
        let store = try ZenithDatabase.inMemory()
        let target = MockSyncTarget()
        let space = try await SpaceQueries.createSpace(store, name: "Doomed", description: nil)
        _ = try await SyncReconciler.runRound(store: store, target: target)  // baseline sync

        try await SpaceQueries.deleteSpace(store, id: space.id)
        let outcome = try await SyncReconciler.runRound(store: store, target: target)

        #expect(outcome.pushed >= 1)
        let remote = await target.remoteRow(.spaces, space.id.uuidString.lowercased())
        #expect(remote == nil)
    }

    @Test("a newer local edit is not undone by an older remote delete")
    func localEditBeatsOlderRemoteDelete() async throws {
        let store = try ZenithDatabase.inMemory()
        let target = MockSyncTarget()
        let space = try await SpaceQueries.createSpace(store, name: "Original", description: nil)
        _ = try await SyncReconciler.runRound(store: store, target: target)  // baseline sync — advances lastPulledAt

        // The remote tombstone must land strictly after the baseline round's
        // cursor (so this round actually pulls it) but strictly before the
        // local edit (so the edit — not the delete — should win).
        try await Task.sleep(for: .milliseconds(20))
        let tombstoneTime = Date()
        try await Task.sleep(for: .milliseconds(20))
        _ = try await SpaceQueries.updateNameAndDescription(store, id: space.id, name: "Edited Locally", description: nil)
        await target.seedRemoteTombstone(SyncTombstone(table: .spaces, id: space.id.uuidString.lowercased(), deletedAt: tombstoneTime))

        let outcome = try await SyncReconciler.runRound(store: store, target: target)

        #expect(outcome.pulled == 1)  // the tombstone was fetched...
        #expect(try await SpaceQueries.getSpaceById(store, id: space.id)?.name == "Edited Locally")  // ...but not applied
    }

    @Test("a second round with nothing changed is a no-op")
    func secondRoundIsNoOp() async throws {
        let store = try ZenithDatabase.inMemory()
        let target = MockSyncTarget()
        _ = try await SpaceQueries.createSpace(store, name: "S", description: nil)

        _ = try await SyncReconciler.runRound(store: store, target: target)
        let outcome = try await SyncReconciler.runRound(store: store, target: target)

        #expect(outcome.pulled == 0)
        #expect(outcome.pushed == 0)
    }

    @Test("a failed round records the error and does not advance cursors")
    func failedRoundRecordsErrorWithoutAdvancingCursors() async throws {
        let store = try ZenithDatabase.inMemory()
        let target = MockSyncTarget()
        await target.setFetchError(MockSyncError(description: "connection refused"))

        do {
            _ = try await SyncReconciler.runRound(store: store, target: target)
            Issue.record("expected runRound to throw")
        } catch {
            // expected
        }

        let state = try await LocalSyncStore.loadSyncState(store, target: target.id)
        #expect(state.lastError?.contains("connection refused") == true)
        #expect(state.lastPulledAt == nil)
        #expect(state.lastSuccessAt == nil)
    }
}
