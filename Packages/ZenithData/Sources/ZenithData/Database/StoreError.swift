/// Errors raised by the local store's query layer. Named `StoreError`
/// rather than `DatabaseError` to avoid colliding with `GRDB.DatabaseError`
/// in files that `import GRDB`.
public enum StoreError: Error, CustomStringConvertible {
    case insertReturnedNoRow
    case notFound
    case invalidEnumValue(String, typeName: String)
    case malformedRow(String)

    public var description: String {
        switch self {
        case .insertReturnedNoRow: return "Insert didn't return the new row."
        case .notFound: return "Record not found."
        case .invalidEnumValue(let raw, let typeName): return "\"\(raw)\" isn't a valid \(typeName)."
        case .malformedRow(let detail): return "Malformed database row: \(detail)."
        }
    }
}
