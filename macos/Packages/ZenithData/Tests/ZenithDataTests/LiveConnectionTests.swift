import Foundation
import Testing

@testable import ZenithData

/// Exercises a real database connection — gated behind an env var so it
/// never runs in normal `swift test`. Run explicitly with:
///   ZENITH_LIVE_DB_TESTS=1 ZENITH_TEST_DATABASE_URL=... swift test --filter LiveConnectionTests
@Suite("ZenithDatabase (live)", .enabled(if: ProcessInfo.processInfo.environment["ZENITH_LIVE_DB_TESTS"] == "1"))
struct LiveConnectionTests {
    @Test("testConnection succeeds against a real Postgres host")
    func testConnectionSucceeds() async throws {
        guard let url = ProcessInfo.processInfo.environment["ZENITH_TEST_DATABASE_URL"] else {
            Issue.record("ZENITH_TEST_DATABASE_URL not set")
            return
        }
        try await ZenithDatabase.testConnection(connectionString: url)
    }

    @Test("diagnostic: print space/issue counts")
    func diagnosticCounts() async throws {
        guard let url = ProcessInfo.processInfo.environment["ZENITH_TEST_DATABASE_URL"] else {
            Issue.record("ZENITH_TEST_DATABASE_URL not set")
            return
        }
        let db = try ZenithDatabase(connectionString: url)
        await db.start()
        let spaces = try await SpaceQueries.getSpaces(db)
        print("DIAGNOSTIC: \(spaces.count) spaces")
        for space in spaces {
            let issues = try await IssueQueries.getIssuesForSpace(db, spaceId: space.id)
            print("DIAGNOSTIC:   - \(space.name) (\(space.slug)): \(issues.count) issues, id=\(space.id)")
        }
        await db.shutdown()
    }

    @Test("issue due/start dates decode as real ISO strings, not garbage bytes")
    func dateColumnsDecodeCorrectly() async throws {
        guard let url = ProcessInfo.processInfo.environment["ZENITH_TEST_DATABASE_URL"] else {
            Issue.record("ZENITH_TEST_DATABASE_URL not set")
            return
        }
        let db = try ZenithDatabase(connectionString: url)
        await db.start()
        let spaces = try await SpaceQueries.getSpaces(db)
        let isoDatePattern = #/^\d{4}-\d{2}-\d{2}$/#
        for space in spaces {
            let issues = try await IssueQueries.getIssuesForSpace(db, spaceId: space.id)
            for issue in issues {
                if let dueDate = issue.dueDate {
                    #expect(dueDate.wholeMatch(of: isoDatePattern) != nil, "bad due_date: \(dueDate)")
                }
                if let startDate = issue.startDate {
                    #expect(startDate.wholeMatch(of: isoDatePattern) != nil, "bad start_date: \(startDate)")
                }
            }
        }
        await db.shutdown()
    }

    @Test("upcomingIssues runs without a date/text operator error")
    func upcomingIssuesRuns() async throws {
        guard let url = ProcessInfo.processInfo.environment["ZENITH_TEST_DATABASE_URL"] else {
            Issue.record("ZENITH_TEST_DATABASE_URL not set")
            return
        }
        let db = try ZenithDatabase(connectionString: url)
        await db.start()
        _ = try await IssueQueries.upcomingIssues(db, daysAhead: 7)
        await db.shutdown()
    }
}
