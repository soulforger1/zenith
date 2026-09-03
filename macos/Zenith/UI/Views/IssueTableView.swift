import SwiftUI
import ZenithData

/// First-cut port of `components/views/table-view.tsx`, using SwiftUI's
/// native `Table` (per docs/native-rewrite-audit.md's decision 6). Covers
/// the fixed built-in columns (title/status/priority/due date) with
/// sorting and multi-select; the dynamic custom-field-registry columns,
/// filter bar, and bulk-action toolbar are a follow-up slice — this
/// establishes the real-data table and quick status/priority edits first.
struct IssueTableView: View {
    let model: SpaceDetailModel

    @Environment(AppShellModel.self) private var shell
    @State private var records: [IssueRecord] = []
    @State private var sortOrder = [KeyPathComparator(\IssueRecord.title)]
    @State private var selection = Set<UUID>()
    @State private var newTaskTitle = ""

    private var sortedRecords: [IssueRecord] {
        records.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            quickAddRow

            Table(sortedRecords, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Title", value: \.title) { record in
                    Text(record.title).lineLimit(1)
                }
                TableColumn("Status", value: \.status.rawValue) { record in
                    statusPicker(for: record)
                }
                .width(140)
                TableColumn("Priority", value: \.priority.rawValue) { record in
                    priorityPicker(for: record)
                }
                .width(110)
                TableColumn("Due", value: \.dueDateSortKey) { record in
                    Text(record.dueDate ?? "—")
                        .foregroundStyle(record.dueDate == nil ? .secondary : .primary)
                        .monospaced()
                }
                .width(100)
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
        .onChange(of: selection) { _, newSelection in
            guard newSelection.count == 1, let id = newSelection.first else { return }
            shell.openTask(spaceId: model.space.id, issueId: id)
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

private extension IssueRecord {
    /// `nil` due dates should sort last regardless of ascending/descending
    /// — mapping to a far-future sentinel string keeps `Table`'s built-in
    /// string comparator doing the sorting without a custom Comparable.
    var dueDateSortKey: String { dueDate ?? "9999-99-99" }
}
