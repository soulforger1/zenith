/// The Postgres type each synced column needs — column names are unique
/// across every table in this schema (no two tables use the same name for
/// differently-typed columns), so one flat lookup covers all 8 tables.
/// This is the generalized version of the per-column `::date` casting the
/// hand-written Postgres queries used to need one call site at a time (see
/// `Database/DynamicUpdate.swift`'s history in `ZenithData`) — every
/// column that isn't plain `text` needs either an explicit cast or a
/// native-typed bind to cross the SQLite-text ⇄ Postgres-typed boundary.
enum PostgresColumnKind {
    case uuid, text, boolean, double, date, timestamp, json, textArray
}

enum PostgresColumnCatalog {
    static func kind(for column: String) -> PostgresColumnKind {
        switch column {
        case "id", "space_id", "milestone_id", "parent_id", "repo_id", "issue_id":
            return .uuid
        case "is_closed", "is_default":
            return .boolean
        case "position":
            return .double
        case "due_date", "start_date":
            return .date
        case "created_at", "updated_at", "closed_at", "cached_at":
            return .timestamp
        case "custom_field_values", "options", "config":
            return .json
        case "tags":
            return .textArray
        default:
            return .text
        }
    }
}
