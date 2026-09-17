import Foundation
import GRDB

/// `updateIssueFields` (and `CustomFieldQueries.updateCustomField`) patch
/// any subset of several independently-optional columns in one statement —
/// building that with compile-time SQL would mean a combinatorial explosion
/// of hand-written cases, so this builds the `SET ...` clause and its
/// positional bindings at runtime instead.
struct DynamicUpdate {
    private(set) var assignments: [String] = []
    private var arguments: [(any DatabaseValueConvertible)?] = []

    /// Sets `column = ?` to a bound value.
    mutating func set(_ column: String, _ value: (any DatabaseValueConvertible)?) {
        assignments.append("\(column) = ?")
        arguments.append(value)
    }

    /// Sets `column = <sql>` where `sql` contains exactly one `?` — used
    /// where the assignment isn't a plain bound value (e.g.
    /// `custom_field_values` merged via a Swift-side read-modify-write,
    /// still expressed here as a normal bound replacement value).
    mutating func setRaw(_ column: String, sql: String, binding value: (any DatabaseValueConvertible)?) {
        assignments.append("\(column) = \(sql)")
        arguments.append(value)
    }

    mutating func setNull(_ column: String) {
        assignments.append("\(column) = NULL")
    }

    var isEmpty: Bool { assignments.isEmpty }

    /// Executes `UPDATE <table> SET ..., updated_at = ? WHERE id = ?
    /// RETURNING *` and returns the updated row, or `nil` if no row
    /// matched. `updated_at` is always bumped, even when `assignments` is
    /// otherwise empty — mirrors the previous Postgres behavior and keeps
    /// the sync layer's "every write touches `updated_at`" invariant.
    func execute(_ db: Database, table: String, id: String, updatedAt: Date = Date()) throws -> Row? {
        var finalAssignments = assignments
        var finalArguments = arguments
        finalAssignments.append("updated_at = ?")
        finalArguments.append(updatedAt)
        finalArguments.append(id)

        let sql = "UPDATE \(table) SET \(finalAssignments.joined(separator: ", ")) WHERE id = ? RETURNING *"
        return try Row.fetchOne(db, sql: sql, arguments: StatementArguments(finalArguments))
    }
}
