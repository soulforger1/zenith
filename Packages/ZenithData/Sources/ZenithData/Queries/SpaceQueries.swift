import Foundation
import GRDB

/// Local-store queries for the `spaces` table.
public enum SpaceQueries {
    private static func map(_ row: Row) throws -> Space {
        Space(
            id: try row.requireUUID("id"),
            name: try row.requireString("name"),
            slug: try row.requireString("slug"),
            description: row.optionalString("description"),
            context: row.optionalString("context"),
            createdAt: try row.requireDate("created_at"),
            updatedAt: try row.requireDate("updated_at")
        )
    }

    public static func getSpaces(_ db: ZenithDatabase) async throws -> [Space] {
        try await db.read { d in
            try Row.fetchAll(d, sql: "SELECT * FROM spaces ORDER BY name ASC").map(map)
        }
    }

    public static func getSpaceBySlug(_ db: ZenithDatabase, slug: String) async throws -> Space? {
        try await db.read { d in
            try getSpaceBySlug(d, slug: slug)
        }
    }

    private static func getSpaceBySlug(_ d: Database, slug: String) throws -> Space? {
        guard let row = try Row.fetchOne(d, sql: "SELECT * FROM spaces WHERE slug = ? LIMIT 1", arguments: [slug]) else {
            return nil
        }
        return try map(row)
    }

    public static func getSpaceById(_ db: ZenithDatabase, id: UUID) async throws -> Space? {
        try await db.read { d in
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM spaces WHERE id = ? LIMIT 1", arguments: [id.databaseText]) else {
                return nil
            }
            return try map(row)
        }
    }

    /// Generates a unique slug from a name, appending -2, -3, ... on collision.
    private static func generateUniqueSlug(_ d: Database, name: String) throws -> String {
        let base = Slug.slugify(name).isEmpty ? "space" : Slug.slugify(name)
        var candidate = base
        var suffix = 2
        while try getSpaceBySlug(d, slug: candidate) != nil {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    public static func createSpace(_ db: ZenithDatabase, name: String, description: String?) async throws -> Space {
        try await db.write { d in
            let slug = try generateUniqueSlug(d, name: name)
            let id = UUID()
            let now = Date()
            try d.execute(
                sql: """
                    INSERT INTO spaces (id, name, slug, description, context, created_at, updated_at)
                    VALUES (?, ?, ?, ?, NULL, ?, ?)
                    """,
                arguments: [id.databaseText, name, slug, description, now, now]
            )
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM spaces WHERE id = ?", arguments: [id.databaseText]) else {
                throw StoreError.insertReturnedNoRow
            }
            return try map(row)
        }
    }

    /// Backs the space settings form. `description == nil` means "leave
    /// unchanged" — an empty form field is normalized to `nil` before it
    /// ever reaches this function, matching the app's existing convention;
    /// there's no way to explicitly clear a space's description through
    /// this path.
    public static func updateNameAndDescription(
        _ db: ZenithDatabase, id: UUID, name: String, description: String?
    ) async throws -> Space? {
        try await db.write { d in
            var update = DynamicUpdate()
            update.set("name", name)
            if let description { update.set("description", description) }
            guard let row = try update.execute(d, table: "spaces", id: id.databaseText) else { return nil }
            return try map(row)
        }
    }

    /// Backs the Settings "context" textarea autosave. Unlike `description`
    /// above, `context` explicitly supports clearing: `nil` here sets the
    /// column to `NULL`.
    public static func updateContext(_ db: ZenithDatabase, id: UUID, context: String?) async throws -> Space? {
        try await db.write { d in
            var update = DynamicUpdate()
            if let context { update.set("context", context) } else { update.setNull("context") }
            guard let row = try update.execute(d, table: "spaces", id: id.databaseText) else { return nil }
            return try map(row)
        }
    }

    public static func deleteSpace(_ db: ZenithDatabase, id: UUID) async throws {
        try await db.write { d in
            try d.execute(sql: "DELETE FROM spaces WHERE id = ?", arguments: [id.databaseText])
        }
    }
}
