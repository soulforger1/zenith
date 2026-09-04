import SwiftUI
import ZenithData

/// Port of `components/views/table-view.tsx`, using SwiftUI's native
/// `Table` (per docs/native-rewrite-audit.md's decision 6). Columns are
/// driven by the view's own `TableViewConfig.visibleFieldIds` (the same
/// data the web build's `ViewSettingsPopover` would edit — there's no
/// native equivalent of that popover yet, so `visibleFieldIds` is
/// effectively read-only here, defaulting to `["status", "priority"]` same
/// as `getOrCreateDefaultViewsForSpace`'s seed), not a fixed hardcoded
/// column set — a real fix from the first-cut version of this view, which
/// always showed Status/Priority/Due regardless of the view's actual
/// config (Due, in particular, was showing even though it isn't in the
/// default `visibleFieldIds` on either the web or native side).
///
/// Status/priority stay interactively editable in-cell (a native
/// enhancement over the web build, which only ever shows a read-only
/// `FieldBadge` there and requires opening the task detail drawer to
/// change them) — every other visible field renders read-only via
/// `FieldDisplayValueView`, matching the web build.
///
/// Filtering is applied here via `FilterEvaluation.apply` over the view's
/// `config.filters` — the same list the shared `ViewFilterBar` (shown
/// above every view) edits, and the same evaluation the Board and Roadmap
/// run, so a filter behaves identically across all three. Still deferred
/// (see docs/native-rewrite-audit.md): keyword search, per-field
/// sort/hide via a column menu, and the view-settings popover for editing
/// `visibleFieldIds`.
struct IssueTableView: View {
    let model: SpaceDetailModel
    let view: ZView

    @Environment(AppShellModel.self) private var shell
    @State private var records: [IssueRecord] = []
    @State private var sortOrder = [KeyPathComparator(\IssueRecord.title)]
    @State private var selection = Set<UUID>()
    @State private var newTaskTitle = ""
    @State private var isBulkWorking = false

    private var registry: [FieldDef] {
        FieldRegistry.build(customFields: model.customFields, milestones: model.milestones, repos: model.repos)
    }

    private var tableConfig: TableViewConfig {
        if case .table(let config) = view.config { return config }
        return TableViewConfig(visibleFieldIds: ["status", "priority"], sort: [], groupByFieldId: nil, filters: [])
    }

    private var visibleFields: [FieldDef] {
        tableConfig.visibleFieldIds.compactMap { FieldRegistry.fieldDef(in: registry, id: $0) }
    }

    private var sortedRecords: [IssueRecord] {
        FilterEvaluation.apply(records, filters: tableConfig.filters, registry: registry)
            .sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            quickAddRow

            if !selection.isEmpty {
                bulkToolbar
            }

            Table(sortedRecords, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Title", value: \.title) { record in
                    Text(record.title).lineLimit(1)
                }
                TableColumnForEach(visibleFields, id: \.id) { field in
                    TableColumn(field.name.uppercased()) { record in
                        cell(for: field, record: record)
                    }
                    .width(min: 90, ideal: 120)
                }
            }
        }
        .task(id: model.issues.map(\.id)) {
            records = await model.issueRecords()
        }
        // The web build makes the whole row clickable to open the task
        // detail drawer (its status/priority cells `stopPropagation` to
        // opt out). `Table` doesn't expose a per-row click separate from
        // selection, so selecting a single row is the native equivalent —
        // matches how Mail/Notes open an item's detail pane on selection.
        // Multi-selection (for the bulk toolbar) intentionally does *not*
        // open the inspector — only a single freshly-made selection does.
        .onChange(of: selection) { _, newSelection in
            guard newSelection.count == 1, let id = newSelection.first else { return }
            shell.openTask(spaceId: model.space.id, issueId: id)
        }
    }

    @ViewBuilder
    private func cell(for field: FieldDef, record: IssueRecord) -> some View {
        switch field {
        case .status:
            statusPicker(for: record)
        case .priority:
            priorityPicker(for: record)
        default:
            FieldDisplayValueView(value: field.displayValue(for: record))
        }
    }

    private var quickAddRow: some View {
        HStack {
            TextField("New task title — press Return to add", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .onSubmit {
                    let title = newTaskTitle
                    guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    newTaskTitle = ""
                    Task { await model.createQuickIssue(title: title, status: .backlog) }
                }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var bulkToolbar: some View {
        HStack(spacing: 10) {
            Text("\(selection.count) selected").font(.caption.weight(.medium))

            Picker("Set status", selection: Binding<IssueStatus?>(get: { nil }, set: { status in
                guard let status else { return }
                Task { await runBulk { await model.bulkUpdateStatus(Array(selection), status: status) } }
            })) {
                Text("Set status").tag(IssueStatus?.none)
                ForEach(IssueStatus.allCases, id: \.self) { status in
                    Text(statusLabel(status)).tag(IssueStatus?.some(status))
                }
            }
            .frame(width: 130)
            .disabled(isBulkWorking)

            Picker("Set priority", selection: Binding<IssuePriority?>(get: { nil }, set: { priority in
                guard let priority else { return }
                Task { await runBulk { await model.bulkUpdatePriority(Array(selection), priority: priority) } }
            })) {
                Text("Set priority").tag(IssuePriority?.none)
                ForEach(IssuePriority.allCases, id: \.self) { priority in
                    Text(PriorityLabel.label(for: priority)).tag(IssuePriority?.some(priority))
                }
            }
            .frame(width: 130)
            .disabled(isBulkWorking)

            Button("Delete", role: .destructive) {
                let ids = Array(selection)
                selection.removeAll()
                Task { await runBulk { await model.bulkDelete(ids) } }
            }
            .disabled(isBulkWorking)

            Spacer()

            if isBulkWorking {
                ProgressView().controlSize(.small)
            }
            Button("Clear") { selection.removeAll() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5))
    }

    private func runBulk(_ action: @escaping () async -> Void) async {
        isBulkWorking = true
        await action()
        selection.removeAll()
        isBulkWorking = false
    }

    private func statusPicker(for record: IssueRecord) -> some View {
        Picker("", selection: Binding(
            get: { record.status },
            set: { newStatus in Task { await model.updateIssueStatus(record.id, status: newStatus) } }
        )) {
            ForEach(IssueStatus.allCases, id: \.self) { status in
                Text(statusLabel(status)).tag(status)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private func priorityPicker(for record: IssueRecord) -> some View {
        Picker("", selection: Binding(
            get: { record.priority },
            set: { newPriority in Task { await model.updateIssuePriority(record.id, priority: newPriority) } }
        )) {
            ForEach(IssuePriority.allCases, id: \.self) { priority in
                Text(PriorityLabel.label(for: priority)).tag(priority)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private func statusLabel(_ status: IssueStatus) -> String {
        switch status {
        case .backlog: return "Backlog"
        case .todo: return "Todo"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }
}
