import PostgresNIO

/// `updateIssueFields` (`lib/db/queries/issues.ts`) patches any subset of
/// 13 independently-optional columns in one statement — building that with
/// compile-time `PostgresQuery` string interpolation would mean a
/// combinatorial explosion of hand-written cases, so this builds the
/// `SET ...` clause and its positional bindings at runtime instead, the
/// same shape Drizzle's own dynamic `.set(values)` produces under the hood.
struct DynamicUpdate {
    private(set) var assignments: [String] = []
    private var bindings = PostgresBindings()

    /// Sets `column = $n` to a bound value.
    mutating func set<Value: PostgresThrowingDynamicTypeEncodable>(_ column: String, _ value: Value) throws {
        assignments.append("\(column) = $\(bindings.count + 1)")
        try bindings.append(value)
    }

    /// Sets `column = $n` to a bound value, using `sqlType` cast on the
    /// placeholder — needed where Postgres can't infer the parameter type
    /// from context alone (e.g. `custom_field_values || $1::jsonb`).
    mutating func set<Value: PostgresThrowingDynamicTypeEncodable>(_ column: String, raw sql: String, binding value: Value) throws {
        assignments.append("\(column) = \(sql.replacingOccurrences(of: "$1", with: "$\(bindings.count + 1)"))")
        try bindings.append(value)
    }

    mutating func setNull(_ column: String) {
        assignments.append("\(column) = NULL")
    }

    var isEmpty: Bool { assignments.isEmpty }

    /// Builds `UPDATE <table> SET ... WHERE id = $n [RETURNING ...]`.
    func buildQuery(table: String, whereIdEquals id: some PostgresThrowingDynamicTypeEncodable, returning columns: String? = nil) throws -> PostgresQuery {
        var finalBindings = bindings
        let idPlaceholder = "$\(finalBindings.count + 1)"
        try finalBindings.append(id)
        let setClause = (assignments + ["updated_at = now()"]).joined(separator: ", ")
        var sql = "UPDATE \(table) SET \(setClause) WHERE id = \(idPlaceholder)"
        if let columns { sql += " RETURNING \(columns)" }
        return PostgresQuery(unsafeSQL: sql, binds: finalBindings)
    }
}
