import Foundation
import GRDB
import Testing

@testable import ZenithData

@Suite("DynamicUpdate")
struct DynamicUpdateTests {
    private func makeQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try zenithMigrator.migrate(queue)
        return queue
    }

    @Test("executes against a real table and always bumps updated_at")
    func executesAndBumpsUpdatedAt() throws {
        let queue = try makeQueue()
        let id = UUID().databaseText
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO spaces (id, name, slug, created_at, updated_at) VALUES (?, 'A', 'a', ?, ?)",
                arguments: [id, Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 0)]
            )
        }

        let updatedRow = try queue.write { db -> Row? in
            var update = DynamicUpdate()
            update.set("name", "B")
            return try update.execute(db, table: "spaces", id: id)
        }

        #expect(updatedRow?["name"] as String? == "B")
        let updatedAt: Date? = updatedRow?["updated_at"]
        #expect(updatedAt != nil)
        #expect(updatedAt!.timeIntervalSinceNow > -5)
    }

    @Test("an empty patch still bumps updated_at")
    func emptyPatchStillBumpsUpdatedAt() throws {
        let queue = try makeQueue()
        let id = UUID().databaseText
        let past = Date(timeIntervalSince1970: 0)
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO spaces (id, name, slug, created_at, updated_at) VALUES (?, 'A', 'a', ?, ?)",
                arguments: [id, past, past]
            )
        }

        let row = try queue.write { db -> Row? in
            let update = DynamicUpdate()
            return try update.execute(db, table: "spaces", id: id)
        }

        let updatedAt: Date? = row?["updated_at"]
        #expect(updatedAt != nil)
        #expect(updatedAt! > past)
    }

    @Test("setNull clears a column")
    func setNullClearsColumn() throws {
        let queue = try makeQueue()
        let id = UUID().databaseText
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO spaces (id, name, slug, description, created_at, updated_at) VALUES (?, 'A', 'a', 'desc', ?, ?)",
                arguments: [id, Date(), Date()]
            )
        }

        let row = try queue.write { db -> Row? in
            var update = DynamicUpdate()
            update.setNull("description")
            return try update.execute(db, table: "spaces", id: id)
        }

        #expect(row?["description"] as String? == nil)
    }
}
