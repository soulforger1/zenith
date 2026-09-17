import Foundation
import GRDB

/// Local-store queries for the `views` table.
public enum ViewQueries {
    private static func map(_ row: Row) throws -> ZView {
        let type = try row.requireEnum("type", ViewType.self)
        return ZView(
            id: try row.requireUUID("id"),
            spaceId: try row.requireUUID("space_id"),
            name: try row.requireString("name"),
            type: type,
            position: try row.requireDouble("position"),
            isDefault: row.requireBool("is_default"),
            config: try ViewConfig.fromJSONText(row.optionalString("config"), type: type),
            createdAt: try row.requireDate("created_at"),
            updatedAt: try row.requireDate("updated_at")
        )
    }

    public static func getViewsForSpace(_ db: ZenithDatabase, spaceId: UUID) async throws -> [ZView] {
        try await db.read { d in
            try Row.fetchAll(d, sql: "SELECT * FROM views WHERE space_id = ? ORDER BY position ASC", arguments: [spaceId.databaseText])
                .map(map)
        }
    }

    public static func getViewById(_ db: ZenithDatabase, id: UUID) async throws -> ZView? {
        try await db.read { d in
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM views WHERE id = ? LIMIT 1", arguments: [id.databaseText]) else {
                return nil
            }
            return try map(row)
        }
    }

    private static func maxPosition(_ d: Database, spaceId: UUID) throws -> Double? {
        try Double.fetchOne(d, sql: "SELECT max(position) FROM views WHERE space_id = ?", arguments: [spaceId.databaseText])
    }

    public static func createView(
        _ db: ZenithDatabase, spaceId: UUID, name: String, type: ViewType, config: ViewConfig
    ) async throws -> ZView {
        try await db.write { d in
            let position = Position.atEnd(try maxPosition(d, spaceId: spaceId))
            let id = UUID()
            let now = Date()
            try d.execute(
                sql: """
                    INSERT INTO views (id, space_id, name, type, config, position, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [id.databaseText, spaceId.databaseText, name, type.rawValue, try config.jsonText(), position, now, now]
            )
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM views WHERE id = ?", arguments: [id.databaseText]) else {
                throw StoreError.insertReturnedNoRow
            }
            return try map(row)
        }
    }

    public static func renameView(_ db: ZenithDatabase, id: UUID, name: String) async throws -> ZView? {
        try await db.write { d in
            try d.execute(sql: "UPDATE views SET name = ?, updated_at = ? WHERE id = ?", arguments: [name, Date(), id.databaseText])
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM views WHERE id = ?", arguments: [id.databaseText]) else { return nil }
            return try map(row)
        }
    }

    public static func updateConfig(_ db: ZenithDatabase, id: UUID, config: ViewConfig) async throws -> ZView? {
        try await db.write { d in
            try d.execute(
                sql: "UPDATE views SET config = ?, updated_at = ? WHERE id = ?",
                arguments: [try config.jsonText(), Date(), id.databaseText]
            )
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM views WHERE id = ?", arguments: [id.databaseText]) else { return nil }
            return try map(row)
        }
    }

    /// Sets `id` as the space's default view, first unsetting every other
    /// view's default flag in the same space so exactly one stays default.
    public static func setDefault(_ db: ZenithDatabase, id: UUID) async throws -> ZView? {
        try await db.write { d in
            guard let currentRow = try Row.fetchOne(d, sql: "SELECT * FROM views WHERE id = ? LIMIT 1", arguments: [id.databaseText]) else {
                return nil
            }
            let current = try map(currentRow)
            let now = Date()
            try d.execute(
                sql: "UPDATE views SET is_default = 0, updated_at = ? WHERE space_id = ? AND id != ?",
                arguments: [now, current.spaceId.databaseText, id.databaseText]
            )
            try d.execute(sql: "UPDATE views SET is_default = 1, updated_at = ? WHERE id = ?", arguments: [now, id.databaseText])
            guard let row = try Row.fetchOne(d, sql: "SELECT * FROM views WHERE id = ?", arguments: [id.databaseText]) else { return nil }
            return try map(row)
        }
    }

    /// Rejects deleting a space's last remaining view — there must always
    /// be something for a bare space link to land on.
    public static func deleteView(_ db: ZenithDatabase, id: UUID) async throws -> ValidationError? {
        try await db.write { d in
            guard let viewRow = try Row.fetchOne(d, sql: "SELECT * FROM views WHERE id = ? LIMIT 1", arguments: [id.databaseText]) else {
                return nil
            }
            let view = try map(viewRow)
            let remaining = try Row.fetchAll(
                d, sql: "SELECT * FROM views WHERE space_id = ? ORDER BY position ASC", arguments: [view.spaceId.databaseText]
            ).map(map)
            guard remaining.count > 1 else {
                return ValidationError(field: "view", message: "A space needs at least one view.")
            }

            try d.execute(sql: "DELETE FROM views WHERE id = ?", arguments: [id.databaseText])
            if view.isDefault, let next = remaining.first(where: { $0.id != id }) {
                try d.execute(sql: "UPDATE views SET is_default = 1 WHERE id = ?", arguments: [next.id.databaseText])
            }
            return nil
        }
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

        // Board stays the default landing view even though Table is listed
        // first in the tab order — `isDefault` and tab position are
        // independent, same as GitHub Projects.
        _ = try await createView(db, spaceId: spaceId, name: "Table", type: .table, config: .defaultConfig(for: .table))
        let board = try await createView(db, spaceId: spaceId, name: "Board", type: .board, config: .defaultConfig(for: .board))
        _ = try await createView(db, spaceId: spaceId, name: "Roadmap", type: .roadmap, config: .defaultConfig(for: .roadmap))
        _ = try await setDefault(db, id: board.id)

        return try await getViewsForSpace(db, spaceId: spaceId)
    }
}
