import Foundation

/// Port of `lib/fields/registry.ts` — the abstraction the Board and
/// Roadmap views (and, eventually, the Table view's dynamic columns/filter
/// bar) build on, treating built-in issue columns and user-defined custom
/// fields identically. Scoped to what those call sites actually need —
/// group-key extraction, patch-building, and date-range resolution —
/// rather than a 1:1 port of the TS `getValue`-closure shape, which
/// doesn't translate naturally to Swift's static typing.
public struct NormalizedOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let color: String?
    public let startDate: String?
    public let durationDays: Int?

    public init(id: String, label: String, color: String?, startDate: String? = nil, durationDays: Int? = nil) {
        self.id = id
        self.label = label
        self.color = color
        self.startDate = startDate
        self.durationDays = durationDays
    }
}

public enum FieldDef: Sendable, Equatable {
    case status
    case priority
    case milestone(options: [NormalizedOption])
    case dueDate
    case startDate
    case custom(CustomField)

    public var id: String {
        switch self {
        case .status: return "status"
        case .priority: return "priority"
        case .milestone: return "milestoneId"
        case .dueDate: return "dueDate"
        case .startDate: return "startDate"
        case .custom(let field): return field.id.uuidString
        }
    }

    public var name: String {
        switch self {
        case .status: return "Status"
        case .priority: return "Priority"
        case .milestone: return "Milestone"
        case .dueDate: return "Due date"
        case .startDate: return "Start date"
        case .custom(let field): return field.name
        }
    }

    public var isBuiltIn: Bool {
        switch self {
        case .custom: return false
        default: return true
        }
    }

    /// True for fields Roadmap can plot a range from — `date` and
    /// `iteration` types, mirrors `hasDateOrIterationField`'s check.
    public var isDateCapable: Bool {
        switch self {
        case .dueDate, .startDate: return true
        case .custom(let field): return field.type == .date || field.type == .iteration
        case .status, .priority, .milestone: return false
        }
    }

    /// True for fields the Board's group-by picker offers — single-value,
    /// discrete-option fields (see `kanban-board.tsx`'s comment on
    /// `withGroupValue`).
    public var isGroupable: Bool {
        switch self {
        case .status, .priority, .milestone: return true
        case .custom(let field): return field.type == .singleSelect || field.type == .iteration
        case .dueDate, .startDate: return false
        }
    }

    public var options: [NormalizedOption] {
        switch self {
        case .status:
            return IssueStatus.allCases.map { NormalizedOption(id: $0.rawValue, label: statusLabel($0), color: statusColor($0)) }
        case .priority:
            return IssuePriority.allCases.map { NormalizedOption(id: $0.rawValue, label: PriorityLabel.label(for: $0), color: nil) }
        case .milestone(let options):
            return options
        case .dueDate, .startDate:
            return []
        case .custom(let field):
            switch field.type {
            case .singleSelect, .multiSelect:
                return field.options.fieldOptions.map { NormalizedOption(id: $0.id, label: $0.name, color: $0.color) }
            case .iteration:
                return field.options.iterationOptions.map {
                    NormalizedOption(id: $0.id, label: $0.title, color: "purple", startDate: $0.startDate, durationDays: $0.durationDays)
                }
            case .text, .number, .date:
                return []
            }
        }
    }

    /// The group bucket an issue falls into for this field — `nil` means
    /// the "no value" bucket. Only meaningful when `isGroupable`.
    public func groupKey(for issue: IssueRecord) -> String? {
        switch self {
        case .status: return issue.status.rawValue
        case .priority: return issue.priority.rawValue
        case .milestone: return issue.milestoneId?.uuidString
        case .dueDate, .startDate: return nil
        case .custom(let field):
            guard case .string(let value) = issue.customFieldValues[field.id.uuidString] else { return nil }
            return value
        }
    }

    /// The `IssueFieldPatch` for moving an issue to `groupKey` on this
    /// field — mirrors `buildFieldPatch`.
    public func patch(forGroupKey groupKey: String?) -> IssueFieldPatch {
        switch self {
        case .status:
            return IssueFieldPatch(status: groupKey.flatMap(IssueStatus.init(rawValue:)) ?? .backlog)
        case .priority:
            return IssueFieldPatch(priority: groupKey.flatMap(IssuePriority.init(rawValue:)) ?? .medium)
        case .milestone:
            return IssueFieldPatch(milestoneId: .some(groupKey.flatMap(UUID.init(uuidString:))))
        case .dueDate, .startDate:
            return IssueFieldPatch()
        case .custom(let field):
            let value: AnyCodableValue = groupKey.map(AnyCodableValue.string) ?? .null
            return IssueFieldPatch(customFieldValues: [field.id.uuidString: value])
        }
    }

    /// A single `YYYY-MM-DD` value for this field on `issue` — `date`-typed
    /// fields only (`iteration` fields resolve through
    /// `RoadmapResolution.resolveRange` instead, since a single date can't
    /// represent an iteration's start+duration). Mirrors `resolveDate`.
    public func dateValue(for issue: IssueRecord) -> String? {
        switch self {
        case .dueDate: return issue.dueDate
        case .startDate: return issue.startDate
        case .custom(let field) where field.type == .date:
            if case .string(let value) = issue.customFieldValues[field.id.uuidString] { return value }
            return nil
        default:
            return nil
        }
    }

    /// The selected iteration option for this field on `issue`, if this is
    /// an iteration-typed field with a value set.
    public func selectedIterationOption(for issue: IssueRecord) -> NormalizedOption? {
        guard case .custom(let field) = self, field.type == .iteration,
            case .string(let optionId) = issue.customFieldValues[field.id.uuidString]
        else { return nil }
        return options.first { $0.id == optionId }
    }

    private func statusLabel(_ status: IssueStatus) -> String {
        switch status {
        case .backlog: return "Backlog"
        case .todo: return "Todo"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }

    private func statusColor(_ status: IssueStatus) -> String {
        switch status {
        case .backlog: return "gray"
        case .todo: return "blue"
        case .inProgress: return "yellow"
        case .done: return "green"
        }
    }
}

/// Port of `resolveRange` — resolves a `[start, end]` pair for an issue
/// given the view's configured start/end fields.
public enum RoadmapResolution {
    public static func resolveRange(startField: FieldDef, endField: FieldDef, issue: IssueRecord) -> (start: String, end: String)? {
        if startField.id == endField.id, case .custom(let field) = startField, field.type == .iteration {
            guard let option = startField.selectedIterationOption(for: issue),
                let start = option.startDate, let duration = option.durationDays
            else { return nil }
            return (start, ISODate.addDays(start, duration))
        }

        let start = startField.dateValue(for: issue)
        let end = endField.dateValue(for: issue)
        guard start != nil || end != nil else { return nil }
        let s = start ?? end!
        let e = end ?? start!
        return s <= e ? (s, e) : (e, s)
    }
}

public enum FieldRegistry {
    /// The full registry — every built-in date/select/milestone field plus
    /// every custom field, matching `buildFieldRegistry`'s scope exactly.
    /// Consumers filter for what they need (`isGroupable` for Board,
    /// `isDateCapable` for Roadmap) rather than this function pre-filtering,
    /// mirroring the TS split of responsibility.
    public static func build(customFields: [CustomField], milestones: [Milestone]) -> [FieldDef] {
        var fields: [FieldDef] = [
            .status, .priority,
            .milestone(options: milestones.map { NormalizedOption(id: $0.id.uuidString, label: $0.title, color: "gray") }),
            .dueDate, .startDate,
        ]
        fields += customFields.map { .custom($0) }
        return fields
    }

    public static func fieldDef(in registry: [FieldDef], id: String) -> FieldDef? {
        registry.first { $0.id == id }
    }
}
