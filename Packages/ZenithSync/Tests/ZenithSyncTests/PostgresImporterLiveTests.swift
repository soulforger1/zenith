import Foundation
import Testing
import ZenithData

@testable import ZenithSync

/// Exercises a real Postgres database — gated behind an env var so it never
/// runs in normal `swift test`. Run explicitly with:
///   ZENITH_LIVE_DB_TESTS=1 ZENITH_TEST_DATABASE_URL=... swift test --filter PostgresImporterLiveTests
@Suite("PostgresImporter (live)", .enabled(if: ProcessInfo.processInfo.environment["ZENITH_LIVE_DB_TESTS"] == "1"))
struct PostgresImporterLiveTests {
    @Test("imports every table into a fresh local store and is safe to re-run")
    func importsIntoFreshStore() async throws {
        guard let url = ProcessInfo.processInfo.environment["ZENITH_TEST_DATABASE_URL"] else {
            Issue.record("ZENITH_TEST_DATABASE_URL not set")
            return
        }
        let store = try ZenithDatabase.inMemory()

        let first = try await PostgresImporter.run(connectionString: url, into: store)
        print("DIAGNOSTIC: imported \(first.spaces) spaces, \(first.issues) issues")

        let localSpaces = try await SpaceQueries.getSpaces(store)
        #expect(localSpaces.count == first.spaces)

        // Re-running is an upsert-by-id merge, not a duplicate.
        let second = try await PostgresImporter.run(connectionString: url, into: store)
        #expect(second.spaces == first.spaces)
        #expect(try await SpaceQueries.getSpaces(store).count == first.spaces)
    }
}
