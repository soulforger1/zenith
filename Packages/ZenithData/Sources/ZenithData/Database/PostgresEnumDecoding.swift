import PostgresNIO

/// `status`/`priority`/`type` columns are plain Postgres `text`, not
/// `jsonb` — decode as `String` and convert via `RawRepresentable`, rather
/// than declaring `PostgresDecodable` conformance on the enums themselves
/// (which would need to special-case the `.jsonb` init path they don't
/// actually use).
extension PostgresCell {
    func decodeEnum<T: RawRepresentable>(_ type: T.Type) throws -> T where T.RawValue == String {
        let raw = try decode(String.self)
        guard let value = T(rawValue: raw) else {
            throw DatabaseError.invalidEnumValue(raw, typeName: String(describing: T.self))
        }
        return value
    }

    func decodeEnum<T: RawRepresentable>(_ type: T?.Type) throws -> T? where T.RawValue == String {
        guard let raw = try decode(String?.self) else { return nil }
        guard let value = T(rawValue: raw) else {
            throw DatabaseError.invalidEnumValue(raw, typeName: String(describing: T.self))
        }
        return value
    }
}
