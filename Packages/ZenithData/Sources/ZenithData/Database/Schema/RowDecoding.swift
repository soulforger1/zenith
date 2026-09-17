import Foundation
import GRDB

/// Canonical text form for every `id` / foreign-key column. GRDB's built-in
/// `UUID` codec stores a 16-byte BLOB — this app stores lowercased text so
/// SQLite ids match Postgres ids byte-for-byte for the sync layer.
extension UUID {
    var databaseText: String { uuidString.lowercased() }
}

/// Typed column accessors used by every `*Queries` row-mapping function.
/// Kept explicit (rather than `FetchableRecord` conformances) to mirror the
/// former `map(_ row: PostgresRow)` shape one-to-one.
extension Row {
    func requireString(_ column: String) throws -> String {
        guard let value: String = self[column] else {
            throw StoreError.malformedRow("missing text column \(column)")
        }
        return value
    }

    func optionalString(_ column: String) -> String? { self[column] }

    func requireUUID(_ column: String) throws -> UUID {
        let text = try requireString(column)
        guard let id = UUID(uuidString: text) else {
            throw StoreError.malformedRow("column \(column) is not a uuid: \(text)")
        }
        return id
    }

    func optionalUUID(_ column: String) throws -> UUID? {
        guard let text: String = self[column] else { return nil }
        guard let id = UUID(uuidString: text) else {
            throw StoreError.malformedRow("column \(column) is not a uuid: \(text)")
        }
        return id
    }

    func requireDate(_ column: String) throws -> Date {
        guard let value: Date = self[column] else {
            throw StoreError.malformedRow("missing timestamp column \(column)")
        }
        return value
    }

    func optionalDate(_ column: String) -> Date? { self[column] }

    func requireDouble(_ column: String) throws -> Double {
        guard let value: Double = self[column] else {
            throw StoreError.malformedRow("missing numeric column \(column)")
        }
        return value
    }

    func requireInt(_ column: String) throws -> Int {
        guard let value: Int = self[column] else {
            throw StoreError.malformedRow("missing integer column \(column)")
        }
        return value
    }

    func requireBool(_ column: String) -> Bool { (self[column] as Bool?) ?? false }

    func requireEnum<T: RawRepresentable>(_ column: String, _ type: T.Type) throws -> T where T.RawValue == String {
        let raw = try requireString(column)
        guard let value = T(rawValue: raw) else {
            throw StoreError.invalidEnumValue(raw, typeName: String(describing: T.self))
        }
        return value
    }

    func optionalEnum<T: RawRepresentable>(_ column: String, _ type: T.Type) throws -> T? where T.RawValue == String {
        guard let raw: String = self[column] else { return nil }
        guard let value = T(rawValue: raw) else {
            throw StoreError.invalidEnumValue(raw, typeName: String(describing: T.self))
        }
        return value
    }

    func jsonMap(_ column: String) throws -> [String: AnyCodableValue] {
        try JSONColumn.decodeMap(self[column])
    }

    func jsonStringArray(_ column: String) throws -> [String] {
        try JSONColumn.decodeStringArray(self[column])
    }
}
