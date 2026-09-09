import Foundation

/// Port of `lib/fields/filter.ts`'s `applyFilters` / `matchesRule` — the
/// evaluation half of the view filter system (the `FilterRule` /
/// `FilterOperator` types in `ViewConfig` are the storage half). Shared by
/// all three views so a filter behaves identically no matter which one is
/// active.

/// The comparable primitive(s) a field yields for filter evaluation —
/// mirrors the TS `field.getValue(issue)` return, flattened to the value
/// kinds `matchesRule` actually compares. Multi-value fields (tags, repos,
/// multi-select) yield several; an unset field yields none.
public enum FilterScalar: Equatable, Sendable {
    case string(String)
    case number(Double)

    public var asString: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
        }
    }

    init?(_ codable: AnyCodableValue) {
        switch codable {
        case .string(let value): self = .string(value)
        case .number(let value): self = .number(value)
        case .bool(let value): self = .string(String(value))
        case .array, .object, .null: return nil
        }
    }
}

extension FieldDef {
    /// The value(s) this field holds on `issue`, for filter matching —
    /// the Swift equivalent of the TS registry's per-field `getValue`
    /// closure, narrowed to what `FilterRule.matches` compares.
    public func filterValues(for issue: IssueRecord) -> [FilterScalar] {
        func nonEmpty(_ value: String?) -> [FilterScalar] {
            guard let value, !value.isEmpty else { return [] }
            return [.string(value)]
        }

        switch self {
        case .status: return [.string(issue.status.rawValue)]
        case .priority: return [.string(issue.priority.rawValue)]
        case .milestone: return issue.milestoneId.map { [.string($0.uuidString)] } ?? []
        case .dueDate: return nonEmpty(issue.dueDate)
        case .startDate: return nonEmpty(issue.startDate)
        case .tags: return issue.tags.map { .string($0) }
        case .repoIds: return issue.repoIds.map { .string($0.uuidString) }
        case .branch: return nonEmpty(issue.branch)
        case .estimate: return nonEmpty(issue.estimate)
        case .custom(let field):
            let raw = issue.customFieldValues[field.id.uuidString]
            switch field.type {
            case .text, .date, .singleSelect, .iteration:
                if case .string(let value) = raw, !value.isEmpty { return [.string(value)] }
                return []
            case .number:
                if case .number(let value) = raw { return [.number(value)] }
                return []
            case .multiSelect:
                guard case .array(let items) = raw else { return [] }
                return items.compactMap { FilterScalar($0) }
            }
        }
    }

    /// Date-typed fields a from/to range filter can be built on — the
    /// built-in due/start dates plus `date`-type custom fields.
    /// `iteration` fields are excluded: their stored value is an option
    /// id, not a `YYYY-MM-DD` string, so `<`/`>` comparisons are
    /// meaningless.
    public var isDateFilterable: Bool {
        switch self {
        case .dueDate, .startDate: return true
        case .custom(let field): return field.type == .date
        case .status, .priority, .milestone, .tags, .repoIds, .branch, .estimate: return false
        }
    }
}

extension FilterRule {
    /// The rule's stored comparison value, decoded from `valueJSON`.
    public var value: AnyCodableValue? {
        guard let valueJSON else { return nil }
        return try? JSONDecoder().decode(AnyCodableValue.self, from: valueJSON)
    }

    /// Encodes `value` into `valueJSON` — the inverse of the `value`
    /// accessor, for building rules in the filter UI.
    public init(fieldId: String, operatorType: FilterOperator, value: AnyCodableValue?) {
        self.init(
            fieldId: fieldId,
            operatorType: operatorType,
            valueJSON: value.flatMap { try? JSONEncoder().encode($0) }
        )
    }

    /// Whether `issue` satisfies this single rule. An unresolvable
    /// `fieldId` passes (matches the TS `if (!field) return true`), so a
    /// stale rule for a since-deleted custom field never hides everything.
    public func matches(issue: IssueRecord, registry: [FieldDef]) -> Bool {
        guard let field = FieldRegistry.fieldDef(in: registry, id: fieldId) else { return true }
        let values = field.filterValues(for: issue)

        switch operatorType {
        case .isEmpty:
            return values.isEmpty
        case .isNotEmpty:
            return !values.isEmpty
        case .isEqual:
            guard let target = value.flatMap(FilterScalar.init) else { return true }
            return values.contains(target)
        case .isNot:
            guard let target = value.flatMap(FilterScalar.init) else { return true }
            return !values.contains(target)
        case .isAnyOf:
            guard case .array(let items)? = value else { return true }
            let targets = items.compactMap { FilterScalar($0) }
            guard !targets.isEmpty else { return true }
            return values.contains { targets.contains($0) }
        case .contains:
            let needle = (value.flatMap(FilterScalar.init)?.asString ?? "").lowercased()
            guard !needle.isEmpty else { return true }
            return values.contains { $0.asString.lowercased().contains(needle) }
        case .before:
            guard let target = value.flatMap(FilterScalar.init)?.asString,
                let actual = values.first?.asString
            else { return false }
            return actual < target
        case .after:
            guard let target = value.flatMap(FilterScalar.init)?.asString,
                let actual = values.first?.asString
            else { return false }
            return actual > target
        }
    }
}

public enum FilterEvaluation {
    /// Keeps only the records satisfying *every* rule (AND semantics,
    /// same as `applyFilters`). An empty rule set is a pass-through.
    public static func apply(
        _ records: [IssueRecord], filters: [FilterRule], registry: [FieldDef]
    ) -> [IssueRecord] {
        guard !filters.isEmpty else { return records }
        return records.filter { record in
            filters.allSatisfy { $0.matches(issue: record, registry: registry) }
        }
    }
}
