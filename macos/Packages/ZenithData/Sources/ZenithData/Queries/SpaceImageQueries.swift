import Foundation
import PostgresNIO

/// Port of `lib/db/queries/space-images.ts`.
public enum SpaceImageQueries {
    private static func map(_ row: PostgresRow) throws -> SpaceImage {
        let r = row.makeRandomAccess()
        return SpaceImage(
            id: try r["id"].decode(UUID.self),
            spaceId: try r["space_id"].decode(UUID.self),
            dataUrl: try r["data_url"].decode(String.self),
            label: try r["label"].decode(String?.self),
            createdAt: try r["created_at"].decode(Date.self)
        )
    }

    private static let columns = "id, space_id, data_url, label, created_at"

    public static func getSpaceImages(_ db: ZenithDatabase, spaceId: UUID) async throws -> [SpaceImage] {
        let rows = try await db.query("SELECT \(unescaped: columns) FROM space_images WHERE space_id = \(spaceId) ORDER BY created_at ASC")
        var results: [SpaceImage] = []
        for try await row in rows { results.append(try map(row)) }
        return results
    }

    public static func addSpaceImage(_ db: ZenithDatabase, spaceId: UUID, dataUrl: String, label: String?) async throws -> SpaceImage {
        let rows = try await db.query("""
            INSERT INTO space_images (space_id, data_url, label) VALUES (\(spaceId), \(dataUrl), \(label))
            RETURNING \(unescaped: columns)
            """)
        for try await row in rows { return try map(row) }
        throw DatabaseError.insertReturnedNoRow
    }

    public static func deleteSpaceImage(_ db: ZenithDatabase, id: UUID) async throws {
        try await db.execute("DELETE FROM space_images WHERE id = \(id)")
    }
}
