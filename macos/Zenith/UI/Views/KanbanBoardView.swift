import SwiftUI
import ZenithData
import UniformTypeIdentifiers

/// Port of `kanban-board.tsx`/`kanban-column.tsx`/`kanban-card.tsx`, using
/// SwiftUI's native `.draggable`/`.dropDestination` per
/// docs/native-rewrite-audit.md's decision 6 (no @dnd-kit/AppKit-interop
/// equivalent needed). Groups by the view's configured field (falls back
/// to status) via the new `FieldRegistry` port; drag-and-drop recomputes
/// fractional position the same way the web build does (`Position.between`),
/// including same-column reordering (drop directly on a card to insert
/// before it, matching the web build's card-to-card precision — dropping
/// in a column's empty space appends to the end). Columns use `.thinMaterial`
/// but cards use a solid, opaque background so they read as distinct
/// tappable/draggable objects against the column's translucent backdrop.
struct KanbanBoardView: View {
    let model: SpaceDetailModel
    let view: ZView

    @State private var records: [IssueRecord] = []

    private var groupByFieldId: String {
        if case .board(let config) = view.config { return config.groupByFieldId }
        return "status"
    }

    private var registry: [FieldDef] {
        FieldRegistry.build(customFields: model.customFields, milestones: model.milestones)
    }

    private var groupField: FieldDef {
        // Defensive: the broadened registry (subtask 4's Roadmap slice)
        // now includes non-groupable fields too, so a stale/bad
        // `groupByFieldId` needs the same "fall back to status" guard the
        // TS side gets implicitly from its view-settings UI only ever
        // offering groupable fields in the first place.
        guard let field = FieldRegistry.fieldDef(in: registry, id: groupByFieldId), field.isGroupable else { return .status }
        return field
    }

    private var columns: [(key: String?, title: String, issues: [IssueRecord])] {
        let field = groupField
        var buckets: [String?: [IssueRecord]] = [:]
        for record in records {
            let key = field.groupKey(for: record)
            buckets[key, default: []].append(record)
        }
        // Sort by fractional `position` (manual drag order), not title —
        // sorting alphabetically would silently discard the user's own
        // ordering on every render.
        let optionColumns = field.options.map { option -> (String?, String, [IssueRecord]) in
            (option.id, option.label.uppercased(), (buckets[option.id] ?? []).sorted { $0.position < $1.position })
        }
        let noValue = (buckets[nil] ?? []).sorted { $0.position < $1.position }
        if noValue.isEmpty {
            return optionColumns
        }
        return optionColumns + [(nil, "NO \(field.name.uppercased())", noValue)]
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(columns, id: \.title) { column in
                    KanbanColumnView(
                        title: column.title,
                        issues: column.issues,
                        spaceId: model.space.id,
                        onDrop: { issueId, beforeId in
                            await move(issueId: issueId, toGroupKey: column.key, beforeIssueId: beforeId)
                        }
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Without this, the ScrollView sizes itself to fit its content
        // (the columns' combined width/height) instead of filling the
        // `NavigationSplitView` detail pane — the symptom was the whole
        // board rendering small and off to one side instead of filling
        // the window.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: model.issues.map(\.id)) {
            records = await model.issueRecords()
        }
    }

    /// `beforeIssueId` is the card the drop landed on (insert immediately
    /// before it) — `nil` means "dropped on the column's empty space",
    /// i.e. append to the end.
    private func move(issueId: UUID, toGroupKey groupKey: String?, beforeIssueId: UUID?) async {
        guard let index = records.firstIndex(where: { $0.id == issueId }) else { return }
        // Exclude the dragged card itself from the destination list before
        // computing where it lands — otherwise reordering within the same
        // column would compute a position relative to its own old slot.
        let destination = (columns.first(where: { $0.key == groupKey })?.issues ?? []).filter { $0.id != issueId }

        let newPosition: Double
        if let beforeIssueId, let beforeIndex = destination.firstIndex(where: { $0.id == beforeIssueId }) {
            let before = beforeIndex > 0 ? destination[beforeIndex - 1].position : nil
            let after = destination[beforeIndex].position
            newPosition = Position.between(before, after)
        } else {
            newPosition = Position.atEnd(destination.last?.position)
        }

        var patch = groupField.patch(forGroupKey: groupKey)
        patch.position = newPosition

        await model.applyPatch(issueId, patch: patch)
        records[index] = applyGroupKey(groupKey, position: newPosition, to: records[index])
    }

    private func applyGroupKey(_ groupKey: String?, position: Double, to record: IssueRecord) -> IssueRecord {
        var updated = record
        updated.position = position
        switch groupField {
        case .status: updated.status = groupKey.flatMap(IssueStatus.init(rawValue:)) ?? .backlog
        case .priority: updated.priority = groupKey.flatMap(IssuePriority.init(rawValue:)) ?? .medium
        case .milestone: updated.milestoneId = groupKey.flatMap(UUID.init(uuidString:))
        case .dueDate, .startDate:
            break // not groupable — never reached in practice, see FieldDef.isGroupable
        case .custom(let field):
            updated.customFieldValues[field.id.uuidString] = groupKey.map(AnyCodableValue.string) ?? .null
        }
        return updated
    }
}

private struct KanbanColumnView: View {
    let title: String
    let issues: [IssueRecord]
    let spaceId: UUID
    /// `(draggedIssueId, dropBeforeIssueId)` — see `KanbanBoardView.move`.
    let onDrop: (UUID, UUID?) async -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(issues.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }

            // Each column scrolls its own cards independently — without
            // this, a column with many cards just overflows the window's
            // bottom edge with no way to reach the rest, since the outer
            // board only scrolls horizontally.
            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    ForEach(issues) { issue in
                        KanbanCardView(issue: issue, spaceId: spaceId)
                            .draggable(issue.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                guard let raw = items.first, let draggedId = UUID(uuidString: raw), draggedId != issue.id else { return false }
                                Task { await onDrop(draggedId, issue.id) }
                                return true
                            }
                    }
                    if issues.isEmpty {
                        Text("No tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // A drop landing here (below the last card, or in an
                    // empty column) always means "append to the end" —
                    // handled by this view's own `.dropDestination` below,
                    // since nothing more specific claims the drop first.
                    Color.clear.frame(height: 24)
                }
            }
        }
        .padding(14)
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let issueId = UUID(uuidString: raw) else { return false }
            Task { await onDrop(issueId, nil) }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

private struct KanbanCardView: View {
    let issue: IssueRecord
    let spaceId: UUID

    @Environment(AppShellModel.self) private var shell

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(Theme.priorityColor(issue.priority)).frame(width: 6, height: 6).padding(.top, 5)
                if issue.parentId != nil {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(issue.title)
                    .font(.callout.weight(.medium))
            }

            if !issue.tags.isEmpty {
                // `FlowLayout`, not `HStack` — an `HStack` squeezes every
                // chip to fit one row, wrapping each chip's *own* text
                // mid-word ("front-end" -> "front-\nend"). Only the row as
                // a whole should wrap; each chip's label always stays on
                // one line (`.fixedSize()` forces that regardless of the
                // width the layout proposes to it).
                FlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(issue.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.monospaced())
                            .fixedSize()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if issue.subtaskCount.total > 0 {
                HStack(spacing: 6) {
                    ProgressView(value: Double(issue.subtaskCount.done), total: Double(issue.subtaskCount.total))
                        .progressViewStyle(.linear)
                        .labelsHidden()
                    Text("\(issue.subtaskCount.done)/\(issue.subtaskCount.total)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A solid, opaque background (not another material) is what
        // actually separates a card from the column's `.thinMaterial`
        // backdrop — two stacked translucent materials read as one flat
        // surface, which was the reported "cards blend into the
        // background" bug.
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            shell.openTask(spaceId: spaceId, issueId: issue.id)
        }
    }
}
