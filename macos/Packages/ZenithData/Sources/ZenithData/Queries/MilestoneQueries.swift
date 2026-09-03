import Foundation
import PostgresNIO

/// Port of `lib/db/queries/milestones.ts`.
public enum MilestoneQueries {
    private static func map(_ row: PostgresRow) throws -> Milestone {
        let r = row.makeRandomAccess()
        return Milestone(
            id: try r["id"].decode(UUID.self),
            spaceId: try r["space_id"].decode(UUID.self),
            title: try r["title"].decode(String.self),
            description: try r["description"].decode(String?.self),
            dueDate: try r["due_date"].decode(String?.self),
            status: try r["status"].decode(String.self),
            closedAt: try r["closed_at"].decode(Date?.self),
            createdAt: try r["created_at"].decode(Date.self),
            updatedAt: try r["updated_at"].decode(Date.self)
        )
    }

    // `due_date::text` — see `IssueQueries.columns`'s comment: decoding a
    // Postgres `date` column straight into `String` without casting reads
    // its raw binary representation as garbage text.
    private static let columns = "id, space_id, title, description, due_date::text AS due_date, status, closed_at, created_at, updated_at"

    public static func getMilestonesForSpace(_ db: ZenithDatabase, spaceId: UUID) async throws -> [Milestone] {
        let rows = try await db.query("""
            SELECT \(unescaped: columns) FROM milestones WHERE space_id = \(spaceId)
            ORDER BY due_date ASC, created_at ASC
            """)
        var results: [Milestone] = []
        for try await row in rows { results.append(try map(row)) }
        return results
    }

    public static func getMilestoneById(_ db: ZenithDatabase, id: UUID) async throws -> Milestone? {
        let rows = try await db.query("SELECT \(unescaped: columns) FROM milestones WHERE id = \(id) LIMIT 1")
        for try await row in rows { return try map(row) }
        return nil
    }

    public static func createMilestone(
        _ db: ZenithDatabase, spaceId: UUID, title: String, description: String?, dueDate: String?
    ) async throws -> Milestone {
        let rows = try await db.query("""
            INSERT INTO milestones (space_id, title, description, due_date)
            VALUES (\(spaceId), \(title), \(description), \(dueDate))
            RETURNING \(unescaped: columns)
            """)
        for try await row in rows { return try map(row) }
        throw DatabaseError.insertReturnedNoRow
    }

    /// `title`/`description`/`dueDate` are all always supplied together by
    /// the edit form's single "save" submit (see `updateMilestoneAction`) —
    /// no partial-patch case exists on the TS side for this table.
    public static func updateMilestone(
        _ db: ZenithDatabase, id: UUID, title: String, description: String?, dueDate: String?
    ) async throws -> Milestone? {
        let rows = try await db.query("""
            UPDATE milestones SET title = \(title), description = \(description), due_date = \(dueDate), updated_at = now()
            WHERE id = \(id) RETURNING \(unescaped: columns)
            """)
        for try await row in rows { return try map(row) }
        return nil
    }

    public static func setClosed(_ db: ZenithDatabase, id: UUID, isClosed: Bool) async throws -> Milestone? {
        let status = isClosed ? "closed" : "open"
        let rows: PostgresRowSequence
        if isClosed {
            rows = try await db.query("""
                UPDATE milestones SET status = \(status), closed_at = now(), updated_at = now()
                WHERE id = \(id) RETURNING \(unescaped: columns)
                """)
        } else {
            rows = try await db.query("""
                UPDATE milestones SET status = \(status), closed_at = NULL, updated_at = now()
                WHERE id = \(id) RETURNING \(unescaped: columns)
                """)
        }
        for try await row in rows { return try map(row) }
        return nil
    }

    public static func deleteMilestone(_ db: ZenithDatabase, id: UUID) async throws {
        try await db.execute("DELETE FROM milestones WHERE id = \(id)")
    }
}
