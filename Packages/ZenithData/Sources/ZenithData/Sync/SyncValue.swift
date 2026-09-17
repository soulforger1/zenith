import Foundation
import GRDB

/// A single column's value in the generic (schema-agnostic) row shape the
/// sync layer moves around — every synced column in the local schema is
/// one of these four SQLite storage classes (no BLOBs are used anywhere in
/// the app's tables). Kept independent of any specific model type so
/// `LocalSyncStore` can read/write *any* synced table without a per-table
/// Swift type, and so `ZenithSync`'s remote targets can build rows without
/// depending on GRDB.
public enum SyncValue: Sendable, Equatable {
    case text(String)
    case integer(Int64)
    case real(Double)
    case null

    /// Convenience for an optional string column (`nil` → `.null`).
    public static func text(_ value: String?) -> SyncValue {
        value.map(SyncValue.text) ?? .null
    }

    /// Convenience for a `Bool` column, stored as SQLite `INTEGER` 0/1.
    public static func bool(_ value: Bool) -> SyncValue {
        .integer(value ? 1 : 0)
    }

    /// Convenience for an optional `Date` column, stored as GRDB's
    /// canonical TEXT format.
    public static func date(_ value: Date?) -> SyncValue {
        value.map { .text(DBDate.string($0)) } ?? .null
    }

    public var stringValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool {
        if case .integer(let value) = self { return value != 0 }
        return false
    }

    public var dateValue: Date? {
        guard case .text(let value) = self else { return nil }
        return DBDate.parse(value)
    }
}

extension SyncValue: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        switch self {
        case .text(let value): return value.databaseValue
        case .integer(let value): return value.databaseValue
        case .real(let value): return value.databaseValue
        case .null: return .null
        }
    }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> SyncValue? {
        switch dbValue.storage {
        case .null: return .null
        case .int64(let value): return .integer(value)
        case .double(let value): return .real(value)
        case .string(let value): return .text(value)
        case .blob: return nil
        }
    }
}
