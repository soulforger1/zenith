import Foundation
import PostgresNIO
import ZenithData

/// Converts a generic `SyncValue` (SQLite-shaped) into a Postgres-typed
/// bind value for the sync target's push side — the remote counterpart of
/// `ZenithData.LocalSyncStore.applyUpsert`'s dynamic SQLite `INSERT`.
enum PostgresRowBinding {
    /// Appends `value` (in `column`'s Postgres type) to `bindings` and
    /// returns the SQL fragment to splice at that position — either a bind
    /// placeholder (`$n`, or `$n::date` where Postgres won't coerce a text
    /// parameter to `date` even in assignment context) or the literal
    /// `NULL` keyword. NULLs are spliced as literal SQL rather than bound
    /// (mirrors the hand-written Postgres queries' `DynamicUpdate.setNull`
    /// convention) since not every `PostgresThrowingDynamicTypeEncodable`
    /// conformance here has a clean optional-binding story.
    static func fragment(column: String, value: SyncValue, appendingTo bindings: inout PostgresBindings) throws -> String {
        let kind = PostgresColumnCatalog.kind(for: column)
        let placeholder = "$\(bindings.count + 1)"

        switch kind {
        case .uuid:
            guard let id = value.stringValue.flatMap({ UUID(uuidString: $0) }) else { return "NULL" }
            bindings.append(id)
            return placeholder
        case .boolean:
            bindings.append(value.boolValue)
            return placeholder
        case .double:
            bindings.append(doubleValue(value) ?? 0)
            return placeholder
        case .date:
            guard let text = value.stringValue else { return "NULL" }
            bindings.append(text)
            return "\(placeholder)::date"
        case .timestamp:
            guard let date = value.dateValue else { return "NULL" }
            bindings.append(date)
            return placeholder
        case .json:
            try bindings.append(try jsonValue(value))
            return placeholder
        case .textArray:
            bindings.append(try stringArrayValue(value))
            return placeholder
        case .text:
            guard let text = value.stringValue else { return "NULL" }
            bindings.append(text)
            return placeholder
        }
    }

    private static func doubleValue(_ value: SyncValue) -> Double? {
        switch value {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }

    private static func jsonValue(_ value: SyncValue) throws -> AnyCodableValue {
        guard let text = value.stringValue, let data = text.data(using: .utf8) else { return .object([:]) }
        return try JSONDecoder().decode(AnyCodableValue.self, from: data)
    }

    private static func stringArrayValue(_ value: SyncValue) throws -> [String] {
        guard let text = value.stringValue, let data = text.data(using: .utf8) else { return [] }
        return try JSONDecoder().decode([String].self, from: data)
    }
}
