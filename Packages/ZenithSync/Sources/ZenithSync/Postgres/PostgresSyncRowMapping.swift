import Foundation
import PostgresNIO
import ZenithData

/// Generic (schema-agnostic) Postgres row → `SyncRow` mapping for the
/// sync target's pull side — the remote counterpart of
/// `ZenithData.LocalSyncStore`'s local row reading. Unlike
/// `PostgresRowMapping` (the Phase-1 importer's *typed*, per-model
/// mapping), this reads every column generically via `SyncValue` so one
/// function handles all 8 tables. The caller's SELECT must already cast
/// `due_date`/`start_date` to `::text` (see `PostgresSyncTarget`'s column
/// lists) — without it, decoding a Postgres `date` cell as text reads its
/// raw binary representation as garbage, same as every other date read in
/// this app.
enum PostgresSyncRowMapping {
    static func syncRow(_ table: SyncTable, _ row: PostgresRow) throws -> SyncRow {
        var columns: [String: SyncValue] = [:]
        for cell in row {
            columns[cell.columnName] = try syncValue(for: cell.columnName, cell: cell)
        }
        guard let id = columns["id"]?.stringValue else {
            throw StoreError.malformedRow("\(table.rawValue) row missing id")
        }
        guard let updatedAt = columns["updated_at"]?.dateValue else {
            throw StoreError.malformedRow("\(table.rawValue) row \(id) missing updated_at")
        }
        return SyncRow(table: table, id: id, updatedAt: updatedAt, columns: columns)
    }

    private static func syncValue(for column: String, cell: PostgresCell) throws -> SyncValue {
        switch PostgresColumnCatalog.kind(for: column) {
        case .uuid:
            guard let id = try cell.decode(UUID?.self) else { return .null }
            return .text(id.uuidString.lowercased())
        case .boolean:
            return .bool(try cell.decode(Bool.self))
        case .double:
            return .real(try cell.decode(Double.self))
        case .date, .text:
            guard let value = try cell.decode(String?.self) else { return .null }
            return .text(value)
        case .timestamp:
            return .date(try cell.decode(Date?.self))
        case .json:
            let raw = try cell.decode(AnyCodableValue.self)
            return .text(String(decoding: try raw.asJSONData(), as: UTF8.self))
        case .textArray:
            let tags = try cell.decode([String].self)
            return .text(String(decoding: try JSONEncoder().encode(tags), as: UTF8.self))
        }
    }
}
