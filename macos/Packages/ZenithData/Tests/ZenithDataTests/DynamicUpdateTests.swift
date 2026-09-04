import Foundation
import Testing

@testable import ZenithData

@Suite("DynamicUpdate")
struct DynamicUpdateTests {
    @Test("raw set renumbers its $1 placeholder to the real bind position")
    func rawSetRenumbers() throws {
        var update = DynamicUpdate()
        try update.set("title", "x")  // $1
        try update.set("due_date", raw: "$1::date", binding: "2026-01-15")  // $2
        let query = try update.buildQuery(table: "issues", whereIdEquals: UUID())
        #expect(query.sql.contains("due_date = $2::date"))
    }

    /// Regression guard for `42804: column "due_date" is of type date but
    /// expression is of type text` — PostgresNIO binds a Swift `String` as
    /// `text`, which Postgres won't coerce to `date` even in an assignment,
    /// so every `date`-column write must cast the placeholder.
    @Test("date columns are written with an explicit ::date cast")
    func dateColumnsAreCast() throws {
        var update = DynamicUpdate()
        try update.set("due_date", raw: "$1::date", binding: "2026-01-15")
        try update.set("start_date", raw: "$1::date", binding: "2026-01-01")
        let query = try update.buildQuery(table: "issues", whereIdEquals: UUID())
        #expect(query.sql.contains("due_date = $1::date"))
        #expect(query.sql.contains("start_date = $2::date"))
    }
}
