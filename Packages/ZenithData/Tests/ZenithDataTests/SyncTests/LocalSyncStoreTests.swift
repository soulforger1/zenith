import Foundation
import GRDB
import Testing

@testable import ZenithData

@Suite("LocalSyncStore")
struct LocalSyncStoreTests {
    private func spaceRow(id: UUID = UUID(), name: String = "Space", updatedAt: Date, createdAt: Date? = nil) -> SyncRow {
        SyncRow(
            table: .spaces, id: id.databaseText, updatedAt: updatedAt,
            columns: [
                "id": .text(id.databaseText), "name": .text(name), "slug": .text(name.lowercased()),
                "description": .null, "context": .null,
                "created_at": .date(createdAt ?? updatedAt), "updated_at": .date(updatedAt),
            ]
        )
    }

    @Test("dirtyRows returns only rows changed after the cursor, in every column")
    func dirtyRowsRespectsCursor() async throws {
        let db = try ZenithDatabase.inMemory()
        let cutoff = Date()
        // GRDB's `Date` text storage has millisecond resolution — without
        // this, `createSpace`'s `updated_at` can land in the same
        // millisecond as `cutoff` and fail the strict `>` comparison below.
        try await Task.sleep(for: .milliseconds(5))
        let space = try await SpaceQueries.createSpace(db, name: "After Cutoff", description: "d")

        let dirty = try await LocalSyncStore.dirtyRows(db, table: .spaces, since: cutoff)
        #expect(dirty.count == 1)
        #expect(dirty[0].id == space.id.databaseText)
        #expect(dirty[0].columns["name"] == .text("After Cutoff"))
        #expect(dirty[0].columns["description"] == .text("d"))

        let none = try await LocalSyncStore.dirtyRows(db, table: .spaces, since: Date())
        #expect(none.isEmpty)
    }

    @Test("localDelta aggregates every table's dirty rows plus tombstones")
    func localDeltaAggregates() async throws {
        let db = try ZenithDatabase.inMemory()
        let cutoff = Date()
        try await Task.sleep(for: .milliseconds(5))  // see dirtyRowsRespectsCursor's comment
        let space = try await SpaceQueries.createSpace(db, name: "S", description: nil)
        let issue = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "T"))
        try await IssueQueries.deleteIssue(db, id: issue.id)

        let delta = try await LocalSyncStore.localDelta(db, since: cutoff)
        #expect(delta.upserts.contains { $0.table == .spaces && $0.id == space.id.databaseText })
        // The issue was created then deleted after `cutoff` — it's gone
        // from the table entirely, so only its tombstone should appear,
        // not an upsert.
        #expect(!delta.upserts.contains { $0.table == .issues })
        #expect(delta.deletes.contains { $0.table == .issues && $0.id == issue.id.databaseText })
    }

    @Test("applyUpsert inserts an absent row")
    func applyUpsertInsertsAbsentRow() async throws {
        let db = try ZenithDatabase.inMemory()
        let id = UUID()
        try await LocalSyncStore.applyUpsert(db, spaceRow(id: id, name: "Remote Space", updatedAt: Date()))

        let space = try await SpaceQueries.getSpaceById(db, id: id)
        #expect(space?.name == "Remote Space")
    }

    @Test("applyUpsert last-write-wins: newer remote overwrites, older remote is ignored")
    func applyUpsertLastWriteWins() async throws {
        let db = try ZenithDatabase.inMemory()
        let id = UUID()
        let baseline = Date()
        try await LocalSyncStore.applyUpsert(db, spaceRow(id: id, name: "V1", updatedAt: baseline))

        // Older remote update — ignored.
        try await LocalSyncStore.applyUpsert(db, spaceRow(id: id, name: "Stale", updatedAt: baseline.addingTimeInterval(-60)))
        #expect(try await SpaceQueries.getSpaceById(db, id: id)?.name == "V1")

        // Newer remote update — applied.
        try await LocalSyncStore.applyUpsert(db, spaceRow(id: id, name: "V2", updatedAt: baseline.addingTimeInterval(60)))
        #expect(try await SpaceQueries.getSpaceById(db, id: id)?.name == "V2")
    }

    @Test("applyUpsert does not resurrect a row deleted locally after the remote's update")
    func applyUpsertDoesNotResurrectNewerLocalDelete() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await SpaceQueries.createSpace(db, name: "Doomed", description: nil)
        try await Task.sleep(for: .milliseconds(5))
        let deleteTime = Date()
        try await SpaceQueries.deleteSpace(db, id: space.id)

        // Remote update from before the local delete — must not resurrect it.
        try await LocalSyncStore.applyUpsert(db, spaceRow(id: space.id, name: "Zombie", updatedAt: deleteTime.addingTimeInterval(-60)))
        #expect(try await SpaceQueries.getSpaceById(db, id: space.id) == nil)

        // Remote update from after the local delete — resurrects it and clears the tombstone.
        try await LocalSyncStore.applyUpsert(db, spaceRow(id: space.id, name: "Reborn", updatedAt: deleteTime.addingTimeInterval(60)))
        #expect(try await SpaceQueries.getSpaceById(db, id: space.id)?.name == "Reborn")

        let tombstoneCount = try await db.read { d in
            try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM sync_tombstones WHERE table_name = 'spaces' AND row_id = ?", arguments: [space.id.databaseText])
        }
        #expect(tombstoneCount == 0)
    }

    @Test("applyDelete respects last-write-wins against a newer local edit")
    func applyDeleteRespectsLastWriteWins() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await SpaceQueries.createSpace(db, name: "S", description: nil)
        try await Task.sleep(for: .milliseconds(5))
        let editTime = Date()
        _ = try await SpaceQueries.updateNameAndDescription(db, id: space.id, name: "Edited", description: nil)

        // An older remote delete loses to the newer local edit.
        try await LocalSyncStore.applyDelete(db, table: .spaces, id: space.id.databaseText, deletedAt: editTime.addingTimeInterval(-60))
        #expect(try await SpaceQueries.getSpaceById(db, id: space.id) != nil)

        // A newer remote delete wins.
        try await LocalSyncStore.applyDelete(db, table: .spaces, id: space.id.databaseText, deletedAt: editTime.addingTimeInterval(60))
        #expect(try await SpaceQueries.getSpaceById(db, id: space.id) == nil)
    }

    @Test("applyUpsert merges an issue_repos link by (issue_id, repo_id) even when the incoming id differs")
    func applyUpsertMergesIssueRepoLinkByNaturalKey() async throws {
        // Regression test: a one-time Postgres import (pre-fix) generated a
        // fresh local `id` for each link instead of preserving Postgres's
        // own — so a later sync pull of that same, unchanged link arrives
        // with a *different* `id` for the same `(issue_id, repo_id)` pair.
        // Conflicting on plain `id` would attempt a second INSERT and trip
        // the table's separate `(issue_id, repo_id)` uniqueness constraint.
        let db = try ZenithDatabase.inMemory()
        let space = try await SpaceQueries.createSpace(db, name: "Space", description: nil)
        let repo = try await RepoQueries.createRepo(db, spaceId: space.id, name: "repo", url: "org/repo")
        let issue = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "T", repoIds: [repo.id]))

        let localLinkId = try await db.read { d in
            try String.fetchOne(d, sql: "SELECT id FROM issue_repos WHERE issue_id = ? AND repo_id = ?", arguments: [issue.id.databaseText, repo.id.databaseText])
        }
        #expect(localLinkId != nil)

        let remoteLinkId = UUID()
        let remoteRow = SyncRow(
            table: .issueRepos, id: remoteLinkId.databaseText, updatedAt: Date().addingTimeInterval(60),
            columns: [
                "id": .text(remoteLinkId.databaseText), "issue_id": .text(issue.id.databaseText),
                "repo_id": .text(repo.id.databaseText), "updated_at": .date(Date().addingTimeInterval(60)),
            ]
        )

        try await LocalSyncStore.applyUpsert(db, remoteRow)  // must not throw a UNIQUE constraint error

        let linkIds = try await db.read { d in
            try String.fetchAll(d, sql: "SELECT id FROM issue_repos WHERE issue_id = ? AND repo_id = ?", arguments: [issue.id.databaseText, repo.id.databaseText])
        }
        #expect(linkIds.count == 1)  // merged, not duplicated
        #expect(linkIds.first == remoteLinkId.databaseText)  // newer row won
    }

    @Test("sync_state round-trips through load/save, including an unseen target's defaults")
    func syncStateRoundTrips() async throws {
        let db = try ZenithDatabase.inMemory()

        let fresh = try await LocalSyncStore.loadSyncState(db, target: "postgres")
        #expect(fresh.lastPulledAt == nil)
        #expect(fresh.lastError == nil)

        let now = Date()
        var state = SyncStateRecord(target: "postgres", lastPulledAt: now, lastPushedAt: now, lastSuccessAt: now, lastError: nil, cursor: nil)
        try await LocalSyncStore.saveSyncState(db, state)

        let reloaded = try await LocalSyncStore.loadSyncState(db, target: "postgres")
        #expect(reloaded.lastPulledAt != nil)
        #expect(abs(reloaded.lastPulledAt!.timeIntervalSince(now)) < 0.01)

        state.lastError = "connection refused"
        try await LocalSyncStore.saveSyncState(db, state)
        #expect(try await LocalSyncStore.loadSyncState(db, target: "postgres").lastError == "connection refused")
    }
}
