import Foundation
import PostgresNIO

/// Port of `lib/db/queries/custom-fields.ts`.
public enum CustomFieldQueries {
    private static func map(_ row: PostgresRow) throws -> CustomField {
        let r = row.makeRandomAccess()
        let type = try r["type"].decodeEnum(CustomFieldType.self)
        let optionsRaw = try r["options"].decode(AnyCodableValue.self)
        return CustomField(
            id: try r["id"].decode(UUID.self),
            spaceId: try r["space_id"].decode(UUID.self),
            key: try r["key"].decode(String.self),
            name: try r["name"].decode(String.self),
            type: type,
            options: try FieldOptions.decode(jsonData: optionsRaw.asJSONData(), type: type),
            position: try r["position"].decode(Double.self),
            createdAt: try r["created_at"].decode(Date.self),
            updatedAt: try r["updated_at"].decode(Date.self)
        )
    }

    private static let columns = "id, space_id, key, name, type, options, position, created_at, updated_at"

    public static func getCustomFieldsForSpace(_ db: ZenithDatabase, spaceId: UUID) async throws -> [CustomField] {
        let rows = try await db.query("""
            SELECT \(unescaped: columns) FROM custom_fields WHERE space_id = \(spaceId)
            ORDER BY position ASC, created_at ASC
            """)
        var results: [CustomField] = []
        for try await row in rows { results.append(try map(row)) }
        return results
    }

    public static func getCustomFieldById(_ db: ZenithDatabase, id: UUID) async throws -> CustomField? {
        let rows = try await db.query("SELECT \(unescaped: columns) FROM custom_fields WHERE id = \(id) LIMIT 1")
        for try await row in rows { return try map(row) }
        return nil
    }

    private static func maxPosition(_ db: ZenithDatabase, spaceId: UUID) async throws -> Double? {
        let rows = try await db.query("SELECT max(position) AS value FROM custom_fields WHERE space_id = \(spaceId)")
        for try await row in rows { return try row.makeRandomAccess()["value"].decode(Double?.self) }
        return nil
    }

    public static func createCustomField(
        _ db: ZenithDatabase, spaceId: UUID, key: String, name: String, type: CustomFieldType, options: FieldOptions
    ) async throws -> CustomField {
        let position = Position.atEnd(try await maxPosition(db, spaceId: spaceId))
        let optionsJSON = try options.asPostgresJSON()
        let rows = try await db.query("""
            INSERT INTO custom_fields (space_id, key, name, type, options, position)
            VALUES (\(spaceId), \(key), \(name), \(type.rawValue), \(optionsJSON), \(position))
            RETURNING \(unescaped: columns)
            """)
        for try await row in rows { return try map(row) }
        throw DatabaseError.insertReturnedNoRow
    }

    /// Partial update — `name`/`options`/`position` are each independently
    /// optional (rename, option-list grow, or drag-reorder can each happen
    /// without touching the others), mirroring `updateCustomField`'s
    /// `Partial<{...}>` input on the TS side.
    public static func updateCustomField(
        _ db: ZenithDatabase, id: UUID, name: String?, options: FieldOptions?, position: Double?
    ) async throws -> CustomField? {
        var update = DynamicUpdate()
        if let name { try update.set("name", name) }
        if let options { try update.set("options", try options.asPostgresJSON()) }
        if let position { try update.set("position", position) }

        let query = try update.buildQuery(table: "custom_fields", whereIdEquals: id, returning: columns)
        let rows = try await db.query(query)
        for try await row in rows { return try map(row) }
        return nil
    }

    public static func deleteCustomField(_ db: ZenithDatabase, id: UUID) async throws {
        try await db.execute("DELETE FROM custom_fields WHERE id = \(id)")
    }
}
