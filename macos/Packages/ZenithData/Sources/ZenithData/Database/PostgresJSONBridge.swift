import Foundation
import PostgresNIO

/// Wires our `Codable` types into PostgresNIO's jsonb encode/decode path.
/// PostgresNIO gives any `Decodable`/`Encodable` type a free jsonb
/// conformance the moment it also declares `PostgresDecodable`/
/// `PostgresEncodable` (see postgres-nio's `JSON+PostgresCodable.swift`) —
/// these are just the opt-in declarations for the types this app stores as
/// jsonb columns.
extension AnyCodableValue: PostgresDecodable, PostgresEncodable {}

/// `issues.custom_field_values` is `Record<string, unknown>` on the TS
/// side — a plain jsonb object — so a `[String: AnyCodableValue]` can bind
/// and decode directly, no intermediate type needed. `@retroactive` because
/// `Dictionary` is a stdlib type we don't own — safe here since this app is
/// the only consumer and the stdlib has no jsonb concept to ever collide
/// with.
extension Dictionary: @retroactive PostgresDecodable, @retroactive PostgresEncodable,
    @retroactive PostgresThrowingDynamicTypeEncodable where Key == String, Value == AnyCodableValue {}

/// `FieldOptions`/`ViewConfig` can't declare `PostgresDecodable` directly:
/// which concrete shape they decode to depends on a *sibling* column
/// (`custom_fields.type` / `views.type`) that isn't available inside
/// `PostgresDecodable`'s fixed init signature. Instead, `Queries` decode
/// the raw jsonb cell as `AnyCodableValue` (which *can* conform directly)
/// and bridge through these helpers once the sibling column is in hand.
extension AnyCodableValue {
    func asJSONData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func from(jsonData: Data) throws -> AnyCodableValue {
        try JSONDecoder().decode(AnyCodableValue.self, from: jsonData)
    }
}

extension FieldOptions {
    /// For binding into an insert/update parameter list.
    func asPostgresJSON() throws -> AnyCodableValue {
        try .from(jsonData: encoded())
    }
}

extension ViewConfig {
    func asPostgresJSON() throws -> AnyCodableValue {
        try .from(jsonData: encoded())
    }
}
