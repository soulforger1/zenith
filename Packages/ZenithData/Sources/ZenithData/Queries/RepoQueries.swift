import Foundation
import GRDB

/// Local-store queries for the `repos` table.
public enum RepoQueries {
    private static func map(_ row: Row) throws -> Repo {
        Repo(
            id: try row.requireUUID("id"),
            spaceId: try row.requireUUID("space_id"),
            name: try row.requireString("name"),
            url: try row.requireString("url"),
            cachedContext: row.optionalString("cached_context"),
            cachedAt: row.optionalDate("cached_at"),
            createdAt: try row.requireDate("created_at"),
            updatedAt: try row.requireDate("updated_at")
        )
    }

    public static func getReposForSpace(_ db: ZenithDatabase, spaceId: UUID) async throws -> [Repo] {
        try await db.read { d in
            try Row.fetchAll(d, sql: "SELECT * FROM repos WHERE space_id = ? ORDER BY name ASC", arguments: [spaceId.databaseText])
                .map(map)
        }
    }

    public static func getRepoById(_ db: ZenithDatabase, id: UUID) async throws -> Repo? {
        try await db.read { d in
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM repos WHERE id = ? LIMIT 1", arguments: [id.databaseText]) else {
                return nil
            }
            return try map(row)
        }
    }

    public static func createRepo(_ db: ZenithDatabase, spaceId: UUID, name: String, url: String) async throws -> Repo {
        try await db.write { d in
            let id = UUID()
            let now = Date()
            try d.execute(
                sql: """
                    INSERT INTO repos (id, space_id, name, url, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [id.databaseText, spaceId.databaseText, name, url, now, now]
            )
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM repos WHERE id = ?", arguments: [id.databaseText]) else {
                throw StoreError.insertReturnedNoRow
            }
            return try map(row)
        }
    }

    public static func updateRepo(_ db: ZenithDatabase, id: UUID, name: String?, url: String?) async throws -> Repo? {
        try await db.write { d in
            var update = DynamicUpdate()
            if let name { update.set("name", name) }
            if let url { update.set("url", url) }
            guard let row = try update.execute(d, table: "repos", id: id.databaseText) else { return nil }
            return try map(row)
        }
    }

    /// Writes the AI-generated summary from a manual "Sync" — the only way
    /// `cachedContext` ever changes; never touched by task-parsing itself.
    public static func setCache(_ db: ZenithDatabase, id: UUID, cachedContext: String) async throws -> Repo? {
        try await db.write { d in
            let now = Date()
            try d.execute(
                sql: "UPDATE repos SET cached_context = ?, cached_at = ?, updated_at = ? WHERE id = ?",
                arguments: [cachedContext, now, now, id.databaseText]
            )
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM repos WHERE id = ?", arguments: [id.databaseText]) else {
                return nil
            }
            return try map(row)
        }
    }

    public static func deleteRepo(_ db: ZenithDatabase, id: UUID) async throws {
        try await db.write { d in
            try d.execute(sql: "DELETE FROM repos WHERE id = ?", arguments: [id.databaseText])
        }
    }
}
