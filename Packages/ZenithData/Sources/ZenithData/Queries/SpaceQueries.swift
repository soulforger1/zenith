import Foundation
import PostgresNIO

/// Port of `lib/db/queries/spaces.ts`.
public enum SpaceQueries {
    private static func map(_ row: PostgresRow) throws -> Space {
        let r = row.makeRandomAccess()
        return Space(
            id: try r["id"].decode(UUID.self),
            name: try r["name"].decode(String.self),
            slug: try r["slug"].decode(String.self),
            description: try r["description"].decode(String?.self),
            context: try r["context"].decode(String?.self),
            createdAt: try r["created_at"].decode(Date.self),
            updatedAt: try r["updated_at"].decode(Date.self)
        )
    }

    private static let columns = "id, name, slug, description, context, created_at, updated_at"

    public static func getSpaces(_ db: ZenithDatabase) async throws -> [Space] {
        let rows = try await db.query("SELECT \(unescaped: columns) FROM spaces ORDER BY name ASC")
        var results: [Space] = []
        for try await row in rows { results.append(try map(row)) }
        return results
    }

    public static func getSpaceBySlug(_ db: ZenithDatabase, slug: String) async throws -> Space? {
        let rows = try await db.query("SELECT \(unescaped: columns) FROM spaces WHERE slug = \(slug) LIMIT 1")
        for try await row in rows { return try map(row) }
        return nil
    }

    public static func getSpaceById(_ db: ZenithDatabase, id: UUID) async throws -> Space? {
        let rows = try await db.query("SELECT \(unescaped: columns) FROM spaces WHERE id = \(id) LIMIT 1")
        for try await row in rows { return try map(row) }
        return nil
    }

    /// Generates a unique slug from a name, appending -2, -3, ... on collision.
    private static func generateUniqueSlug(_ db: ZenithDatabase, name: String) async throws -> String {
        let base = Slug.slugify(name).isEmpty ? "space" : Slug.slugify(name)
        var candidate = base
        var suffix = 2
        while try await getSpaceBySlug(db, slug: candidate) != nil {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    public static func createSpace(_ db: ZenithDatabase, name: String, description: String?) async throws -> Space {
        let slug = try await generateUniqueSlug(db, name: name)
        let rows = try await db.query("""
            INSERT INTO spaces (name, description, slug) VALUES (\(name), \(description), \(slug))
            RETURNING \(unescaped: columns)
            """)
        for try await row in rows { return try map(row) }
        throw DatabaseError.insertReturnedNoRow
    }

    /// Backs the space settings form (`updateSpaceAction`). `description ==
    /// nil` means "leave unchanged" — mirrors the TS side's behavior
    /// exactly: `spaceInputSchema`'s `description` is `.optional()`, and an
    /// empty form field maps to `undefined` before it ever reaches
    /// `updateSpace`, which Drizzle's `.set()` treats as "don't touch this
    /// column" (not "clear it") when a key is `undefined`. There is no way
    /// to explicitly clear a space's description through this path — that
    /// limitation is real on the TS side too, not lost in translation.
    public static func updateNameAndDescription(
        _ db: ZenithDatabase, id: UUID, name: String, description: String?
    ) async throws -> Space? {
        let rows: PostgresRowSequence
        if let description {
            rows = try await db.query("""
                UPDATE spaces SET name = \(name), description = \(description), updated_at = now()
                WHERE id = \(id) RETURNING \(unescaped: columns)
                """)
        } else {
            rows = try await db.query("""
                UPDATE spaces SET name = \(name), updated_at = now()
                WHERE id = \(id) RETURNING \(unescaped: columns)
                """)
        }
        for try await row in rows { return try map(row) }
        return nil
    }

    /// Backs the Settings "context" textarea autosave
    /// (`updateSpaceContextAction`). Unlike `description` above, `context`
    /// explicitly supports clearing: `nil` here sets the column to `NULL`
    /// (the TS side passes `context.trim() || null`, never `undefined`).
    public static func updateContext(_ db: ZenithDatabase, id: UUID, context: String?) async throws -> Space? {
        let rows = try await db.query("""
            UPDATE spaces SET context = \(context), updated_at = now()
            WHERE id = \(id) RETURNING \(unescaped: columns)
            """)
        for try await row in rows { return try map(row) }
        return nil
    }

    public static func deleteSpace(_ db: ZenithDatabase, id: UUID) async throws {
        try await db.execute("DELETE FROM spaces WHERE id = \(id)")
    }
}

public enum DatabaseError: Error, CustomStringConvertible {
    case insertReturnedNoRow
    case notFound
    case invalidEnumValue(String, typeName: String)

    public var description: String {
        switch self {
        case .insertReturnedNoRow: return "Insert didn't return the new row."
        case .notFound: return "Record not found."
        case .invalidEnumValue(let raw, let typeName): return "\"\(raw)\" isn't a valid \(typeName)."
        }
    }
}
