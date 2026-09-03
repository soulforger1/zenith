import Foundation
import PostgresNIO

/// Port of `lib/db/queries/views.ts`.
public enum ViewQueries {
    private static func map(_ row: PostgresRow) throws -> ZView {
        let r = row.makeRandomAccess()
        let type = try r["type"].decodeEnum(ViewType.self)
        let configRaw = try r["config"].decode(AnyCodableValue.self)
        return ZView(
            id: try r["id"].decode(UUID.self),
            spaceId: try r["space_id"].decode(UUID.self),
            name: try r["name"].decode(String.self),
            type: type,
            position: try r["position"].decode(Double.self),
            isDefault: try r["is_default"].decode(Bool.self),
            config: try ViewConfig.decode(jsonData: configRaw.asJSONData(), type: type),
            createdAt: try r["created_at"].decode(Date.self),
            updatedAt: try r["updated_at"].decode(Date.self)
        )
    }

    private static let columns = "id, space_id, name, type, position, is_default, config, created_at, updated_at"

    public static func getViewsForSpace(_ db: ZenithDatabase, spaceId: UUID) async throws -> [ZView] {
        let rows = try await db.query("SELECT \(unescaped: columns) FROM views WHERE space_id = \(spaceId) ORDER BY position ASC")
        var results: [ZView] = []
        for try await row in rows { results.append(try map(row)) }
        return results
    }

    public static func getViewById(_ db: ZenithDatabase, id: UUID) async throws -> ZView? {
        let rows = try await db.query("SELECT \(unescaped: columns) FROM views WHERE id = \(id) LIMIT 1")
        for try await row in rows { return try map(row) }
        return nil
    }

    private static func maxPosition(_ db: ZenithDatabase, spaceId: UUID) async throws -> Double? {
        let rows = try await db.query("SELECT max(position) AS value FROM views WHERE space_id = \(spaceId)")
        for try await row in rows { return try row.makeRandomAccess()["value"].decode(Double?.self) }
        return nil
    }

    public static func createView(
        _ db: ZenithDatabase, spaceId: UUID, name: String, type: ViewType, config: ViewConfig
    ) async throws -> ZView {
        let position = Position.atEnd(try await maxPosition(db, spaceId: spaceId))
        let configJSON = try config.asPostgresJSON()
        let rows = try await db.query("""
            INSERT INTO views (space_id, name, type, config, position)
            VALUES (\(spaceId), \(name), \(type.rawValue), \(configJSON), \(position))
            RETURNING \(unescaped: columns)
            """)
        for try await row in rows { return try map(row) }
        throw DatabaseError.insertReturnedNoRow
    }

    public static func renameView(_ db: ZenithDatabase, id: UUID, name: String) async throws -> ZView? {
        let rows = try await db.query("UPDATE views SET name = \(name), updated_at = now() WHERE id = \(id) RETURNING \(unescaped: columns)")
        for try await row in rows { return try map(row) }
        return nil
    }

    public static func updateConfig(_ db: ZenithDatabase, id: UUID, config: ViewConfig) async throws -> ZView? {
        let configJSON = try config.asPostgresJSON()
        let rows = try await db.query("UPDATE views SET config = \(configJSON), updated_at = now() WHERE id = \(id) RETURNING \(unescaped: columns)")
        for try await row in rows { return try map(row) }
        return nil
    }

    /// Sets `id` as the space's default view, first unsetting every other
    /// view's default flag in the same space so exactly one stays default
    /// — mirrors `updateView`'s `isDefault`-only branch.
    public static func setDefault(_ db: ZenithDatabase, id: UUID) async throws -> ZView? {
        guard let current = try await getViewById(db, id: id) else { return nil }
        try await db.execute("""
            UPDATE views SET is_default = false, updated_at = now()
            WHERE space_id = \(current.spaceId) AND id != \(id)
            """)
        let rows = try await db.query("UPDATE views SET is_default = true, updated_at = now() WHERE id = \(id) RETURNING \(unescaped: columns)")
        for try await row in rows { return try map(row) }
        return nil
    }

    /// Rejects deleting a space's last remaining view — there must always
    /// be something for a bare `/spaces/[slug]` to redirect to.
    public static func deleteView(_ db: ZenithDatabase, id: UUID) async throws -> ValidationError? {
        guard let view = try await getViewById(db, id: id) else { return nil }
        let remaining = try await getViewsForSpace(db, spaceId: view.spaceId)
        guard remaining.count > 1 else {
            return ValidationError(field: "view", message: "A space needs at least one view.")
        }

        try await db.execute("DELETE FROM views WHERE id = \(id)")
        if view.isDefault, let next = remaining.first(where: { $0.id != id }) {
            try await db.execute("UPDATE views SET is_default = true WHERE id = \(next.id)")
        }
        return nil
    }

    private static let starterFieldsSpec: [(key: String, name: String, type: CustomFieldType, optionNames: [(name: String, color: String)])] = [
        ("assignees", "Assignees", .multiSelect, []),
        ("size", "Size", .singleSelect, [("XS", "gray"), ("S", "blue"), ("M", "yellow"), ("L", "orange"), ("XL", "red")]),
    ]

    /// If a space has no views yet, seed the standard trio — Table
    /// (default), Board, Roadmap — plus the two starter custom fields
    /// (Assignees, Size) referenced by the Table/Board defaults. Idempotent:
    /// returns the existing views untouched if there are already any.
    public static func getOrCreateDefaultViewsForSpace(_ db: ZenithDatabase, spaceId: UUID) async throws -> [ZView] {
        let existing = try await getViewsForSpace(db, spaceId: spaceId)
        if !existing.isEmpty { return existing }

        for starter in starterFieldsSpec {
            let options = starter.optionNames.map { FieldOption(id: UUID().uuidString, name: $0.name, color: $0.color) }
            _ = try await CustomFieldQueries.createCustomField(
                db, spaceId: spaceId, key: starter.key, name: starter.name, type: starter.type, options: .fields(options)
            )
        }

        // Board stays the default landing view (carried forward from this
        // app's earlier "Board is the default view" decision) even though
        // Table is listed first in the tab order — `isDefault` and tab
        // position are independent, same as GitHub Projects.
        let table = try await createView(db, spaceId: spaceId, name: "Table", type: .table, config: .defaultConfig(for: .table))
        let board = try await createView(db, spaceId: spaceId, name: "Board", type: .board, config: .defaultConfig(for: .board))
        _ = try await createView(db, spaceId: spaceId, name: "Roadmap", type: .roadmap, config: .defaultConfig(for: .roadmap))
        _ = try await setDefault(db, id: board.id)

        return try await getViewsForSpace(db, spaceId: spaceId)
    }
}
