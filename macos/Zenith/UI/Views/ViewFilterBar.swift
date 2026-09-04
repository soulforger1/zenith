import SwiftUI
import ZenithData

/// Shared filter bar shown above every saved view (Table / Board /
/// Roadmap). It edits the *current* view's `config.filters`; all three
/// views run the same `FilterEvaluation.apply` over that list, so a filter
/// behaves identically no matter which view is active.
///
/// Three guided controls, all writing the same `[FilterRule]`:
///  - **Milestone** — multi-select of the space's milestones (or "No milestone")
///  - **Date range** — an inclusive from/to window on a chosen date field
///  - **More filters** — a generic field / operator / value row for anything else
struct ViewFilterBar: View {
    let registry: [FieldDef]
    let milestones: [Milestone]
    let filters: [FilterRule]
    let onChange: ([FilterRule]) -> Void

    @State private var isEditorPresented = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isEditorPresented = true
            } label: {
                Label("Filter", systemImage: filters.isEmpty
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill")
            }
            .buttonStyle(.bordered)
            .help("Filter which tasks this view shows")
            .popover(isPresented: $isEditorPresented, arrowEdge: .bottom) {
                FilterEditor(registry: registry, milestones: milestones, filters: filters, onChange: onChange)
            }

            if !filters.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(filters.enumerated()), id: \.offset) { index, rule in
                            FilterChip(
                                text: FilterSummary.text(for: rule, registry: registry, milestones: milestones)
                            ) {
                                var next = filters
                                next.remove(at: index)
                                onChange(next)
                            }
                        }
                    }
                }
                .layoutPriority(1)

                Button("Clear") { onChange([]) }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct FilterChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text).lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove this filter")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filter: \(text)")
        .accessibilityHint("Activate to remove")
    }
}

// MARK: - Editor

private struct FilterEditor: View {
    let registry: [FieldDef]
    let milestones: [Milestone]
    let filters: [FilterRule]
    let onChange: ([FilterRule]) -> Void

    /// Which date field the range picker targets. Seeded from an existing
    /// date-range rule if there is one, else "Due date".
    @State private var dateField: String = FieldDef.dueDate.id

    private var dateFields: [FieldDef] { registry.filter(\.isDateFilterable) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                milestoneSection
                Divider()
                dateRangeSection
                Divider()
                otherSection
            }
            .padding(16)
        }
        .frame(width: 340)
        .frame(maxHeight: 460)
        .onAppear {
            if let existing = filters.first(where: isDateRangeRule) { dateField = existing.fieldId }
        }
    }

    // MARK: Milestone

    private var selectedMilestoneIds: Set<String> {
        guard let rule = filters.first(where: { $0.fieldId == FieldDef.milestone(options: []).id }),
            rule.operatorType == .isAnyOf, case .array(let items)? = rule.value
        else { return [] }
        return Set(items.compactMap { if case .string(let value) = $0 { return value }; return nil })
    }

    private var noMilestoneChecked: Bool {
        filters.contains { $0.fieldId == FieldDef.milestone(options: []).id && $0.operatorType == .isEmpty }
    }

    private var milestoneSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Milestone")
            if milestones.isEmpty {
                Text("No milestones in this space yet.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Toggle("No milestone", isOn: Binding(
                    get: { noMilestoneChecked },
                    set: { on in setMilestoneFilter(ids: [], noMilestone: on) }
                ))
                ForEach(milestones) { milestone in
                    Toggle(milestone.title, isOn: Binding(
                        get: { selectedMilestoneIds.contains(milestone.id.uuidString) },
                        set: { on in
                            var ids = selectedMilestoneIds
                            if on { ids.insert(milestone.id.uuidString) } else { ids.remove(milestone.id.uuidString) }
                            setMilestoneFilter(ids: ids, noMilestone: false)
                        }
                    ))
                }
            }
        }
    }

    private func setMilestoneFilter(ids: Set<String>, noMilestone: Bool) {
        let fieldId = FieldDef.milestone(options: []).id
        var next = filters.filter { $0.fieldId != fieldId }
        if noMilestone {
            next.append(FilterRule(fieldId: fieldId, operatorType: .isEmpty, value: nil))
        } else if !ids.isEmpty {
            next.append(FilterRule(
                fieldId: fieldId, operatorType: .isAnyOf,
                value: .array(ids.sorted().map { .string($0) })))
        }
        onChange(next)
    }

    // MARK: Date range

    private func isDateRangeRule(_ rule: FilterRule) -> Bool {
        guard rule.operatorType == .before || rule.operatorType == .after else { return false }
        return registry.first { $0.id == rule.fieldId }?.isDateFilterable ?? false
    }

    private func dateBound(_ op: FilterOperator) -> Date? {
        guard let rule = filters.first(where: { $0.fieldId == dateField && $0.operatorType == op }),
            case .string(let stored)? = rule.value
        else { return nil }
        // Stored bounds are nudged one day outward (see setDateBound) — pull back in.
        let inclusive = op == .after ? ISODate.addDays(stored, 1) : ISODate.addDays(stored, -1)
        return ISODate.parse(inclusive)
    }

    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Date range")
            if dateFields.isEmpty {
                Text("This space has no date fields.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Field", selection: Binding(
                    get: { dateField },
                    set: { newField in
                        // Move any existing bounds onto the newly chosen field,
                        // clearing every other date field's range rules so the
                        // window only ever lives on one field.
                        let from = dateBound(.after)
                        let to = dateBound(.before)
                        dateField = newField
                        var next = filters.filter { !isDateRangeRule($0) }
                        if let from { next.append(makeBoundRule(.after, date: from)) }
                        if let to { next.append(makeBoundRule(.before, date: to)) }
                        onChange(next)
                    }
                )) {
                    ForEach(dateFields, id: \.id) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)

                optionalDateRow("From", op: .after)
                optionalDateRow("To", op: .before)
            }
        }
    }

    @ViewBuilder
    private func optionalDateRow(_ label: String, op: FilterOperator) -> some View {
        let bound = dateBound(op)
        HStack {
            Toggle(label, isOn: Binding(
                get: { bound != nil },
                set: { on in setDateBound(op, date: on ? (bound ?? Date()) : nil) }
            ))
            .fixedSize()
            if let bound {
                DatePicker("", selection: Binding(
                    get: { bound },
                    set: { setDateBound(op, date: $0) }
                ), displayedComponents: .date)
                .labelsHidden()
            }
            Spacer()
        }
    }

    private func setDateBound(_ op: FilterOperator, date: Date?) {
        var next = filters.filter { !($0.fieldId == dateField && $0.operatorType == op) }
        if let date { next.append(makeBoundRule(op, date: date)) }
        onChange(next)
    }

    /// Builds one range-bound rule on the current `dateField`. The bound
    /// is nudged one day outward so the strict `<` / `>` operator yields
    /// an *inclusive* [from, to] window (undone on read in `dateBound`).
    private func makeBoundRule(_ op: FilterOperator, date: Date) -> FilterRule {
        let iso = ISODate.string(from: date)
        let stored = op == .after ? ISODate.addDays(iso, -1) : ISODate.addDays(iso, 1)
        return FilterRule(fieldId: dateField, operatorType: op, value: .string(stored))
    }

    // MARK: Other

    private var otherIndices: [Int] {
        filters.indices.filter { i in
            let rule = filters[i]
            let isMilestone = rule.fieldId == FieldDef.milestone(options: []).id
            return !isMilestone && !isDateRangeRule(rule)
        }
    }

    private var otherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("More filters")
            ForEach(otherIndices, id: \.self) { index in
                FilterRuleRow(
                    registry: registry,
                    rule: filters[index],
                    onChange: { updated in
                        var next = filters
                        next[index] = updated
                        onChange(next)
                    },
                    onRemove: {
                        var next = filters
                        next.remove(at: index)
                        onChange(next)
                    }
                )
            }
            Button {
                var next = filters
                next.append(FilterRule(fieldId: FieldDef.status.id, operatorType: .isNotEmpty, value: nil))
                onChange(next)
            } label: {
                Label("Add filter", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}

// MARK: - Generic rule row

private struct FilterRuleRow: View {
    let registry: [FieldDef]
    let rule: FilterRule
    let onChange: (FilterRule) -> Void
    let onRemove: () -> Void

    private var field: FieldDef? { registry.first { $0.id == rule.fieldId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Picker("", selection: Binding(
                    get: { rule.fieldId },
                    set: { newId in
                        let newField = registry.first { $0.id == newId }
                        let ops = FilterOptions.operators(for: newField)
                        onChange(FilterRule(
                            fieldId: newId,
                            operatorType: ops.first ?? .isNotEmpty,
                            value: nil))
                    }
                )) {
                    ForEach(registry, id: \.id) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .frame(maxWidth: 120)

                Picker("", selection: Binding(
                    get: { rule.operatorType },
                    set: { onChange(FilterRule(fieldId: rule.fieldId, operatorType: $0, value: rule.value)) }
                )) {
                    ForEach(FilterOptions.operators(for: field), id: \.self) { op in
                        Text(FilterOptions.label(op)).tag(op)
                    }
                }
                .labelsHidden()

                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove filter")
            }

            valueEditor
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var valueEditor: some View {
        if rule.operatorType == .isEmpty || rule.operatorType == .isNotEmpty {
            EmptyView()
        } else if let field, case .options(let options) = FilterOptions.inputKind(for: field), !options.isEmpty {
            if rule.operatorType == .isAnyOf {
                Menu(anyOfSummary(options)) {
                    ForEach(options) { option in
                        Toggle(option.label, isOn: Binding(
                            get: { anyOfSelection.contains(option.id) },
                            set: { on in
                                var ids = anyOfSelection
                                if on { ids.insert(option.id) } else { ids.remove(option.id) }
                                onChange(FilterRule(
                                    fieldId: rule.fieldId, operatorType: .isAnyOf,
                                    value: .array(ids.sorted().map { .string($0) })))
                            }
                        ))
                    }
                }
            } else {
                Picker("", selection: Binding(
                    get: { stringValue },
                    set: { onChange(FilterRule(fieldId: rule.fieldId, operatorType: rule.operatorType, value: .string($0))) }
                )) {
                    Text("—").tag("")
                    ForEach(options) { Text($0.label).tag($0.id) }
                }
                .labelsHidden()
            }
        } else if let field, case .date = FilterOptions.inputKind(for: field) {
            DatePicker("", selection: Binding(
                get: { stringValue.isEmpty ? Date() : ISODate.parse(stringValue) },
                set: { onChange(FilterRule(fieldId: rule.fieldId, operatorType: rule.operatorType, value: .string(ISODate.string(from: $0)))) }
            ), displayedComponents: .date)
            .labelsHidden()
        } else if let field, case .number = FilterOptions.inputKind(for: field) {
            TextField("Value", text: Binding(
                get: { stringValue },
                set: { text in
                    let value: AnyCodableValue = Double(text).map { .number($0) } ?? .string(text)
                    onChange(FilterRule(fieldId: rule.fieldId, operatorType: rule.operatorType, value: value))
                }
            ))
            .textFieldStyle(.roundedBorder)
        } else {
            TextField("Value", text: Binding(
                get: { stringValue },
                set: { onChange(FilterRule(fieldId: rule.fieldId, operatorType: rule.operatorType, value: .string($0))) }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    private var stringValue: String {
        switch rule.value {
        case .string(let s): return s
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
        default: return ""
        }
    }

    private var anyOfSelection: Set<String> {
        guard case .array(let items)? = rule.value else { return [] }
        return Set(items.compactMap { if case .string(let s) = $0 { return s }; return nil })
    }

    private func anyOfSummary(_ options: [NormalizedOption]) -> String {
        let labels = options.filter { anyOfSelection.contains($0.id) }.map(\.label)
        return labels.isEmpty ? "Select…" : labels.joined(separator: ", ")
    }
}

// MARK: - Field/operator metadata

private enum FilterOptions {
    enum InputKind {
        case options([NormalizedOption])
        case freeText
        case number
        case date
    }

    static func inputKind(for field: FieldDef) -> InputKind {
        switch field {
        case .status, .priority, .milestone, .repoIds:
            return .options(field.options)
        case .dueDate, .startDate:
            return .date
        case .branch, .estimate, .tags:
            return .freeText
        case .custom(let f):
            switch f.type {
            case .text: return .freeText
            case .number: return .number
            case .date: return .date
            case .singleSelect, .multiSelect, .iteration: return .options(field.options)
            }
        }
    }

    static func operators(for field: FieldDef?) -> [FilterOperator] {
        guard let field else { return [.isNotEmpty, .isEmpty] }
        switch inputKind(for: field) {
        case .options:
            return [.isEqual, .isNot, .isAnyOf, .isEmpty, .isNotEmpty]
        case .freeText:
            return [.contains, .isEqual, .isNot, .isEmpty, .isNotEmpty]
        case .number:
            return [.isEqual, .isNot, .isEmpty, .isNotEmpty]
        case .date:
            return [.isEqual, .before, .after, .isEmpty, .isNotEmpty]
        }
    }

    static func label(_ op: FilterOperator) -> String {
        switch op {
        case .isEqual: return "is"
        case .isNot: return "is not"
        case .isAnyOf: return "is any of"
        case .contains: return "contains"
        case .isEmpty: return "is empty"
        case .isNotEmpty: return "is not empty"
        case .before: return "is before"
        case .after: return "is after"
        }
    }
}

// MARK: - Chip labels

enum FilterSummary {
    static func text(for rule: FilterRule, registry: [FieldDef], milestones: [Milestone]) -> String {
        let field = registry.first { $0.id == rule.fieldId }
        let name = field?.name ?? rule.fieldId

        switch rule.operatorType {
        case .isEmpty:
            return field?.id == FieldDef.milestone(options: []).id ? "No milestone" : "\(name) is empty"
        case .isNotEmpty:
            return "\(name) is not empty"
        case .isAnyOf:
            return "\(name): \(valueLabels(rule, field: field).joined(separator: ", "))"
        case .before:
            return "\(name) before \(displayDate(rule))"
        case .after:
            return "\(name) after \(displayDate(rule))"
        case .isEqual:
            return "\(name): \(valueLabels(rule, field: field).first ?? "—")"
        case .isNot:
            return "\(name) ≠ \(valueLabels(rule, field: field).first ?? "—")"
        case .contains:
            return "\(name) contains “\(scalarString(rule.value))”"
        }
    }

    private static func valueLabels(_ rule: FilterRule, field: FieldDef?) -> [String] {
        let ids: [String]
        switch rule.value {
        case .array(let items): ids = items.compactMap { if case .string(let s) = $0 { return s }; return nil }
        case .string(let s): ids = [s]
        case .number(let n): ids = [n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)]
        default: ids = []
        }
        guard let field else { return ids }
        let options = field.options
        return ids.map { id in options.first { $0.id == id }?.label ?? id }
    }

    private static func displayDate(_ rule: FilterRule) -> String {
        // Undo the one-day outward nudge from `setDateBound`.
        guard case .string(let stored)? = rule.value else { return "?" }
        return rule.operatorType == .after ? ISODate.addDays(stored, 1) : ISODate.addDays(stored, -1)
    }

    private static func scalarString(_ value: AnyCodableValue?) -> String {
        switch value {
        case .string(let s): return s
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
        default: return ""
        }
    }
}
