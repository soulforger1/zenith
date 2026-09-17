import Foundation
import GRDB

/// Local-store queries for the `custom_fields` table.
public enum CustomFieldQueries {
    private static func map(_ row: Row) throws -> CustomField {
        let type = try row.requireEnum("type", CustomFieldType.self)
        return CustomField(
            id: try row.requireUUID("id"),
            spaceId: try row.requireUUID("space_id"),
            key: try row.requireString("key"),
            name: try row.requireString("name"),
            type: type,
            options: try FieldOptions.fromJSONText(row.optionalString("options"), type: type),
            position: try row.requireDouble("position"),
            createdAt: try row.requireDate("created_at"),
            updatedAt: try row.requireDate("updated_at")
        )
    }

    public static func getCustomFieldsForSpace(_ db: ZenithDatabase, spaceId: UUID) async throws -> [CustomField] {
        try await db.read { d in
            try Row.fetchAll(
                d, sql: "SELECT * FROM custom_fields WHERE space_id = ? ORDER BY position ASC, created_at ASC",
                arguments: [spaceId.databaseText]
            ).map(map)
        }
    }

    public static func getCustomFieldById(_ db: ZenithDatabase, id: UUID) async throws -> CustomField? {
        try await db.read { d in
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM custom_fields WHERE id = ? LIMIT 1", arguments: [id.databaseText]) else {
                return nil
            }
            return try map(row)
        }
    }

    private static func maxPosition(_ d: Database, spaceId: UUID) throws -> Double? {
        try Double.fetchOne(d, sql: "SELECT max(position) FROM custom_fields WHERE space_id = ?", arguments: [spaceId.databaseText])
    }

    public static func createCustomField(
        _ db: ZenithDatabase, spaceId: UUID, key: String, name: String, type: CustomFieldType, options: FieldOptions
    ) async throws -> CustomField {
        try await db.write { d in
            let position = Position.atEnd(try maxPosition(d, spaceId: spaceId))
            let id = UUID()
            let now = Date()
            try d.execute(
                sql: """
                    INSERT INTO custom_fields (id, space_id, key, name, type, options, position, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [id.databaseText, spaceId.databaseText, key, name, type.rawValue, try options.jsonText(), position, now, now]
            )
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM custom_fields WHERE id = ?", arguments: [id.databaseText]) else {
                throw StoreError.insertReturnedNoRow
            }
            return try map(row)
        }
    }

    /// Partial update — `name`/`options`/`position` are each independently
    /// optional (rename, option-list grow, or drag-reorder can each happen
    /// without touching the others).
    public static func updateCustomField(
        _ db: ZenithDatabase, id: UUID, name: String?, options: FieldOptions?, position: Double?
    ) async throws -> CustomField? {
        try await db.write { d in
            var update = DynamicUpdate()
            if let name { update.set("name", name) }
            if let options { update.set("options", try options.jsonText()) }
            if let position { update.set("position", position) }
            guard let row = try update.execute(d, table: "custom_fields", id: id.databaseText) else { return nil }
            return try map(row)
        }
    }

    public static func deleteCustomField(_ db: ZenithDatabase, id: UUID) async throws {
        try await db.write { d in
            try d.execute(sql: "DELETE FROM custom_fields WHERE id = ?", arguments: [id.databaseText])
        }
    }
}
