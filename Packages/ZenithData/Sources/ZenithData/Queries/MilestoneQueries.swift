import Foundation
import GRDB

/// Local-store queries for the `milestones` table.
public enum MilestoneQueries {
    private static func map(_ row: Row) throws -> Milestone {
        Milestone(
            id: try row.requireUUID("id"),
            spaceId: try row.requireUUID("space_id"),
            title: try row.requireString("title"),
            description: row.optionalString("description"),
            dueDate: row.optionalString("due_date"),
            status: try row.requireString("status"),
            closedAt: row.optionalDate("closed_at"),
            createdAt: try row.requireDate("created_at"),
            updatedAt: try row.requireDate("updated_at")
        )
    }

    public static func getMilestonesForSpace(_ db: ZenithDatabase, spaceId: UUID) async throws -> [Milestone] {
        try await db.read { d in
            try Row.fetchAll(
                d, sql: "SELECT * FROM milestones WHERE space_id = ? ORDER BY due_date ASC, created_at ASC",
                arguments: [spaceId.databaseText]
            ).map(map)
        }
    }

    public static func getMilestoneById(_ db: ZenithDatabase, id: UUID) async throws -> Milestone? {
        try await db.read { d in
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM milestones WHERE id = ? LIMIT 1", arguments: [id.databaseText]) else {
                return nil
            }
            return try map(row)
        }
    }

    public static func createMilestone(
        _ db: ZenithDatabase, spaceId: UUID, title: String, description: String?, dueDate: String?
    ) async throws -> Milestone {
        try await db.write { d in
            let id = UUID()
            let now = Date()
            try d.execute(
                sql: """
                    INSERT INTO milestones (id, space_id, title, description, due_date, status, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, 'open', ?, ?)
                    """,
                arguments: [id.databaseText, spaceId.databaseText, title, description, dueDate, now, now]
            )
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM milestones WHERE id = ?", arguments: [id.databaseText]) else {
                throw StoreError.insertReturnedNoRow
            }
            return try map(row)
        }
    }

    /// `title`/`description`/`dueDate` are always supplied together by the
    /// edit form's single "save" submit — no partial-patch case exists for
    /// this table.
    public static func updateMilestone(
        _ db: ZenithDatabase, id: UUID, title: String, description: String?, dueDate: String?
    ) async throws -> Milestone? {
        try await db.write { d in
            try d.execute(
                sql: "UPDATE milestones SET title = ?, description = ?, due_date = ?, updated_at = ? WHERE id = ?",
                arguments: [title, description, dueDate, Date(), id.databaseText]
            )
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM milestones WHERE id = ?", arguments: [id.databaseText]) else {
                return nil
            }
            return try map(row)
        }
    }

    public static func setClosed(_ db: ZenithDatabase, id: UUID, isClosed: Bool) async throws -> Milestone? {
        try await db.write { d in
            let now = Date()
            let status = isClosed ? "closed" : "open"
            try d.execute(
                sql: "UPDATE milestones SET status = ?, closed_at = ?, updated_at = ? WHERE id = ?",
                arguments: [status, isClosed ? now : nil, now, id.databaseText]
            )
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM milestones WHERE id = ?", arguments: [id.databaseText]) else {
                return nil
            }
            return try map(row)
        }
    }

    public static func deleteMilestone(_ db: ZenithDatabase, id: UUID) async throws {
        try await db.write { d in
            try d.execute(sql: "DELETE FROM milestones WHERE id = ?", arguments: [id.databaseText])
        }
    }
}
