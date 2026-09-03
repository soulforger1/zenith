/// Port of the enum-like string unions in `lib/db/schema.ts`.

public enum IssueStatus: String, Codable, CaseIterable, Sendable {
    case backlog, todo
    case inProgress = "in_progress"
    case done
}

public enum IssuePriority: String, Codable, CaseIterable, Sendable {
    case low, medium, high
}

public enum CustomFieldType: String, Codable, CaseIterable, Sendable {
    case text, number, date
    case singleSelect = "single_select"
    case multiSelect = "multi_select"
    case iteration
}

public enum ViewType: String, Codable, CaseIterable, Sendable {
    case table, board, roadmap
}
