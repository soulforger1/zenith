import Foundation
import Testing
import ZenithData

@testable import ZenithSync

/// Exercises `PostgresSyncTarget` against a real Postgres database — gated
/// behind an env var so it never runs in normal `swift test`. Requires the
/// `0007_sync_tombstones` migration (`db/migrations/`) to already be
/// applied to that database. Run explicitly with:
///   ZENITH_LIVE_DB_TESTS=1 ZENITH_TEST_DATABASE_URL=... swift test --filter PostgresSyncTargetLiveTests
@Suite("PostgresSyncTarget (live)", .enabled(if: ProcessInfo.processInfo.environment["ZENITH_LIVE_DB_TESTS"] == "1"))
struct PostgresSyncTargetLiveTests {
    @Test("a locally-created space round-trips through a real Postgres database")
    func roundTripsThroughRealPostgres() async throws {
        guard let url = ProcessInfo.processInfo.environment["ZENITH_TEST_DATABASE_URL"] else {
            Issue.record("ZENITH_TEST_DATABASE_URL not set")
            return
        }
        let target = PostgresSyncTarget(connectionString: url)

        // Push a uniquely-named space up.
        let sender = try ZenithDatabase.inMemory()
        let space = try await SpaceQueries.createSpace(sender, name: "ZenithSync live test \(UUID().uuidString.prefix(8))", description: nil)
        let firstRound = try await SyncReconciler.runRound(store: sender, target: target)
        #expect(firstRound.pushed >= 1)

        // A fresh local store pulling since the beginning of time should see it.
        let receiver = try ZenithDatabase.inMemory()
        let secondRound = try await SyncReconciler.runRound(store: receiver, target: target)
        #expect(secondRound.pulled >= 1)
        #expect(try await SpaceQueries.getSpaceById(receiver, id: space.id)?.name == space.name)

        // Re-running the sender's round with nothing changed is a no-op.
        let thirdRound = try await SyncReconciler.runRound(store: sender, target: target)
        #expect(thirdRound.pulled == 0)
        #expect(thirdRound.pushed == 0)

        // Clean up — delete locally and push the tombstone so the live
        // database doesn't accumulate test rows across runs.
        try await SpaceQueries.deleteSpace(sender, id: space.id)
        _ = try await SyncReconciler.runRound(store: sender, target: target)
    }
}
