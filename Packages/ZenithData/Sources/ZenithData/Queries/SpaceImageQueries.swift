import Foundation
import GRDB

/// Local-store queries for the `space_images` table.
public enum SpaceImageQueries {
    private static func map(_ row: Row) throws -> SpaceImage {
        SpaceImage(
            id: try row.requireUUID("id"),
            spaceId: try row.requireUUID("space_id"),
            dataUrl: try row.requireString("data_url"),
            label: row.optionalString("label"),
            createdAt: try row.requireDate("created_at")
        )
    }

    public static func getSpaceImages(_ db: ZenithDatabase, spaceId: UUID) async throws -> [SpaceImage] {
        try await db.read { d in
            try Row.fetchAll(
                d, sql: "SELECT * FROM space_images WHERE space_id = ? ORDER BY created_at ASC",
                arguments: [spaceId.databaseText]
            ).map(map)
        }
    }

    public static func addSpaceImage(_ db: ZenithDatabase, spaceId: UUID, dataUrl: String, label: String?) async throws -> SpaceImage {
        try await db.write { d in
            let id = UUID()
            let now = Date()
            try d.execute(
                sql: """
                    INSERT INTO space_images (id, space_id, data_url, label, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [id.databaseText, spaceId.databaseText, dataUrl, label, now, now]
            )
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM space_images WHERE id = ?", arguments: [id.databaseText]) else {
                throw StoreError.insertReturnedNoRow
            }
            return try map(row)
        }
    }

    public static func deleteSpaceImage(_ db: ZenithDatabase, id: UUID) async throws {
        try await db.write { d in
            try d.execute(sql: "DELETE FROM space_images WHERE id = ?", arguments: [id.databaseText])
        }
    }
}
