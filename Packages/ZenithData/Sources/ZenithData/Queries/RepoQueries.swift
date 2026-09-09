import Foundation
import PostgresNIO

/// Port of `lib/db/queries/repos.ts`.
public enum RepoQueries {
    private static func map(_ row: PostgresRow) throws -> Repo {
        let r = row.makeRandomAccess()
        return Repo(
            id: try r["id"].decode(UUID.self),
            spaceId: try r["space_id"].decode(UUID.self),
            name: try r["name"].decode(String.self),
            url: try r["url"].decode(String.self),
            cachedContext: try r["cached_context"].decode(String?.self),
            cachedAt: try r["cached_at"].decode(Date?.self),
            createdAt: try r["created_at"].decode(Date.self),
            updatedAt: try r["updated_at"].decode(Date.self)
        )
    }

    private static let columns = "id, space_id, name, url, cached_context, cached_at, created_at, updated_at"

    public static func getReposForSpace(_ db: ZenithDatabase, spaceId: UUID) async throws -> [Repo] {
        let rows = try await db.query("SELECT \(unescaped: columns) FROM repos WHERE space_id = \(spaceId) ORDER BY name ASC")
        var results: [Repo] = []
        for try await row in rows { results.append(try map(row)) }
        return results
    }

    public static func getRepoById(_ db: ZenithDatabase, id: UUID) async throws -> Repo? {
        let rows = try await db.query("SELECT \(unescaped: columns) FROM repos WHERE id = \(id) LIMIT 1")
        for try await row in rows { return try map(row) }
        return nil
    }

    public static func createRepo(_ db: ZenithDatabase, spaceId: UUID, name: String, url: String) async throws -> Repo {
        let rows = try await db.query("""
            INSERT INTO repos (space_id, name, url) VALUES (\(spaceId), \(name), \(url))
            RETURNING \(unescaped: columns)
            """)
        for try await row in rows { return try map(row) }
        throw DatabaseError.insertReturnedNoRow
    }

    public static func updateRepo(_ db: ZenithDatabase, id: UUID, name: String?, url: String?) async throws -> Repo? {
        let rows: PostgresRowSequence
        switch (name, url) {
        case (.some(let n), .some(let u)):
            rows = try await db.query("UPDATE repos SET name = \(n), url = \(u), updated_at = now() WHERE id = \(id) RETURNING \(unescaped: columns)")
        case (.some(let n), nil):
            rows = try await db.query("UPDATE repos SET name = \(n), updated_at = now() WHERE id = \(id) RETURNING \(unescaped: columns)")
        case (nil, .some(let u)):
            rows = try await db.query("UPDATE repos SET url = \(u), updated_at = now() WHERE id = \(id) RETURNING \(unescaped: columns)")
        case (nil, nil):
            rows = try await db.query("SELECT \(unescaped: columns) FROM repos WHERE id = \(id) LIMIT 1")
        }
        for try await row in rows { return try map(row) }
        return nil
    }

    /// Writes the AI-generated summary from a manual "Sync" — the only way
    /// `cachedContext` ever changes; never touched by task-parsing itself.
    public static func setCache(_ db: ZenithDatabase, id: UUID, cachedContext: String) async throws -> Repo? {
        let rows = try await db.query("""
            UPDATE repos SET cached_context = \(cachedContext), cached_at = now(), updated_at = now()
            WHERE id = \(id) RETURNING \(unescaped: columns)
            """)
        for try await row in rows { return try map(row) }
        return nil
    }

    public static func deleteRepo(_ db: ZenithDatabase, id: UUID) async throws {
        try await db.execute("DELETE FROM repos WHERE id = \(id)")
    }
}
