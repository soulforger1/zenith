import SwiftUI
import ZenithData
import UniformTypeIdentifiers

/// Port of `kanban-board.tsx`/`kanban-column.tsx`/`kanban-card.tsx`. Groups by
/// the view's configured field (falls back to status) via the `FieldRegistry`
/// port; drag-and-drop recomputes fractional position the same way the web
/// build does (`Position.between`), including same-column reordering.
///
/// Drag tracking uses AppKit-style `.onDrag`/`DropDelegate` (not the newer
/// `.draggable`/`.dropDestination`) because we need the *live* drag location
/// during the hover — that's what drives the insertion indicator that shows
/// exactly which slot the card will land in, and a card-shaped drag preview
/// that follows the cursor. `.dropDestination` only exposes a bool
/// `isTargeted`, which isn't enough to place a between-cards indicator.
///
/// The dropped card is reflected in the UI immediately (optimistic), before
/// the Postgres write, so it never visibly "sticks" in its old slot.
struct KanbanBoardView: View {
    let model: SpaceDetailModel
    let view: ZView

    @State private var records: [IssueRecord] = []
    /// The card currently being dragged — used to dim it in place and to
    /// exclude it from the destination slot maths while it hovers.
    @State private var draggingId: UUID?

    private var groupByFieldId: String {
        if case .board(let config) = view.config { return config.groupByFieldId }
        return "status"
    }

    private var registry: [FieldDef] {
        FieldRegistry.build(customFields: model.customFields, milestones: model.milestones, repos: model.repos)
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

    private var filteredRecords: [IssueRecord] {
        FilterEvaluation.apply(records, filters: view.config.filters, registry: registry)
    }

    private var columns: [(key: String?, title: String, issues: [IssueRecord])] {
        let field = groupField
        var buckets: [String?: [IssueRecord]] = [:]
        for record in filteredRecords {
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
                        draggingId: draggingId,
                        onDragStart: { draggingId = $0 },
                        onDragEnd: { draggingId = nil },
                        onMove: { issueId, beforeId in
                            Task { await move(issueId: issueId, toGroupKey: column.key, beforeIssueId: beforeId) }
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
        // Catch-all behind the columns: a drag released on empty board
        // space (or abandoned) still needs to un-dim the source card.
        // Columns claim the drop first, so this only fires on a miss.
        .onDrop(of: [.plainText], isTargeted: nil) { _ in
            draggingId = nil
            return false
        }
        .task(id: model.issues.map(\.id)) {
            records = await model.issueRecords()
        }
    }

    /// `beforeIssueId` is the card the drop should land immediately above —
    /// `nil` means "append to the end of the column".
    private func move(issueId: UUID, toGroupKey groupKey: String?, beforeIssueId: UUID?) async {
        draggingId = nil // belt-and-suspenders; the drop delegate already did this
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

        // Reflect the move in the UI immediately — `applyPatch` below runs a
        // multi-round-trip transaction against a remote Postgres, and waiting
        // on it before touching `records` is what made the card visibly
        // "stick" in its old column for a few seconds after the drop. Snapshot
        // the old value so a failed write can be rolled back.
        let previous = records[index]
        withAnimation(.easeOut(duration: 0.14)) {
            records[index] = applyGroupKey(groupKey, position: newPosition, to: records[index])
        }

        let persisted = await model.applyPatch(issueId, patch: patch)
        if !persisted {
            withAnimation(.easeOut(duration: 0.14)) { records[index] = previous }
        }
    }

    private func applyGroupKey(_ groupKey: String?, position: Double, to record: IssueRecord) -> IssueRecord {
        var updated = record
        updated.position = position
        switch groupField {
        case .status: updated.status = groupKey.flatMap(IssueStatus.init(rawValue:)) ?? .backlog
        case .priority: updated.priority = groupKey.flatMap(IssuePriority.init(rawValue:)) ?? .medium
        case .milestone: updated.milestoneId = groupKey.flatMap(UUID.init(uuidString:))
        case .dueDate, .startDate, .tags, .repoIds, .branch, .estimate:
            break // not groupable — never reached in practice, see FieldDef.isGroupable
        case .custom(let field):
            updated.customFieldValues[field.id.uuidString] = groupKey.map(AnyCodableValue.string) ?? .null
        }
        return updated
    }
}

/// Where a hovering drag will insert: directly above a given card, or at the
/// column's tail.
private enum DropSlot: Equatable {
    case before(UUID)
    case atEnd
}

/// Collects each card's frame (in the column's coordinate space) so the drop
/// delegate can turn a drag's Y position into a `DropSlot`.
private struct CardFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct KanbanColumnView: View {
    private static let coordSpace = "kanban-column"

    let title: String
    let issues: [IssueRecord]
    let spaceId: UUID
    let draggingId: UUID?
    let onDragStart: (UUID) -> Void
    let onDragEnd: () -> Void
    /// `(draggedIssueId, dropBeforeIssueId)` — see `KanbanBoardView.move`.
    let onMove: (UUID, UUID?) -> Void

    @State private var cardFrames: [UUID: CGRect] = [:]
    @State private var dropSlot: DropSlot?

    /// The drop indicator is only ever shown while a drag is genuinely in
    /// flight. `dropSlot` on its own can be left stale by a stray
    /// `dropUpdated` that SwiftUI fires right after `performDrop` (no
    /// matching `dropExited`), which is what left the accent border and
    /// insertion capsule stuck on screen after a drop. Gating on
    /// `draggingId` — cleared the instant any drag ends — makes that
    /// impossible regardless of what `dropSlot` holds.
    private var activeSlot: DropSlot? {
        draggingId == nil ? nil : dropSlot
    }

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
                        if activeSlot == .before(issue.id) {
                            insertionIndicator
                        }
                        KanbanCardView(issue: issue, spaceId: spaceId)
                            .opacity(draggingId == issue.id ? 0.35 : 1)
                            .background(frameReader(for: issue.id))
                            .onDrag {
                                // Deferred: mutating observed board state
                                // synchronously here trips "modifying state
                                // during view update".
                                let id = issue.id
                                DispatchQueue.main.async { onDragStart(id) }
                                return NSItemProvider(object: issue.id.uuidString as NSString)
                            } preview: {
                                DragPreviewCard(title: issue.title, priority: issue.priority)
                            }
                    }
                    if issues.isEmpty && activeSlot == nil {
                        Text("No tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if activeSlot == .atEnd {
                        insertionIndicator
                    }
                    // Keeps a drop target below the last card (and gives an
                    // empty column something to hover) — a drop here reads
                    // as `.atEnd`.
                    Color.clear.frame(height: 24)
                }
                .padding(.top, 1)
                .animation(.easeOut(duration: 0.14), value: issues.map(\.id))
                .animation(.easeOut(duration: 0.12), value: activeSlot)
            }
        }
        .padding(14)
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(activeSlot != nil ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .coordinateSpace(name: Self.coordSpace)
        // When a drag ends anywhere, drop the stale hover state too.
        .onChange(of: draggingId) { _, newValue in
            if newValue == nil { dropSlot = nil }
        }
        .onPreferenceChange(CardFrameKey.self) { cardFrames = $0 }
        .onDrop(
            of: [.plainText],
            delegate: ColumnDropDelegate(
                slot: $dropSlot,
                orderedCardIds: issues.map(\.id),
                cardFrames: cardFrames,
                draggingId: draggingId,
                onDragEnd: onDragEnd,
                onPerform: onMove
            )
        )
    }

    private var insertionIndicator: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 3)
            .padding(.horizontal, 6)
            .transition(.opacity)
    }

    private func frameReader(for id: UUID) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: CardFrameKey.self,
                value: [id: geo.frame(in: .named(Self.coordSpace))]
            )
        }
    }
}

/// Turns the live drag location into a `DropSlot` by comparing it against the
/// column's card frames, and drives the insertion indicator as the cursor
/// moves. `performDrop` reads the dragged id out of the item provider.
private struct ColumnDropDelegate: DropDelegate {
    @Binding var slot: DropSlot?
    let orderedCardIds: [UUID]
    let cardFrames: [UUID: CGRect]
    let draggingId: UUID?
    let onDragEnd: () -> Void
    let onPerform: (UUID, UUID?) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        setSlot(computeSlot(at: info.location))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        setSlot(computeSlot(at: info.location))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        setSlot(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = computeSlot(at: info.location)
        // End the drag *now*, synchronously — before any stray post-drop
        // `dropUpdated` — so the indicator/border can't reappear.
        onDragEnd()
        slot = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let raw = value as? String, let draggedId = UUID(uuidString: raw) else { return }
            let beforeId: UUID? = {
                if case .before(let id) = target { return id }
                return nil
            }()
            DispatchQueue.main.async { onPerform(draggedId, beforeId) }
        }
        return true
    }

    private func setSlot(_ next: DropSlot?) {
        guard next != slot else { return }
        withAnimation(.easeOut(duration: 0.12)) { slot = next }
    }

    /// First card (top to bottom, skipping the one being dragged) whose
    /// vertical midpoint sits below the cursor → insert above it. Past the
    /// last card → append.
    private func computeSlot(at location: CGPoint) -> DropSlot {
        for id in orderedCardIds {
            if id == draggingId { continue }
            guard let rect = cardFrames[id] else { continue }
            if location.y < rect.midY {
                return .before(id)
            }
        }
        return .atEnd
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

/// The card-shaped image that follows the cursor during a drag. Deliberately
/// a standalone mini-view (not `KanbanCardView`) — the drag preview is
/// rendered outside the normal environment, so it can't rely on
/// `AppShellModel` being injected.
private struct DragPreviewCard: View {
    let title: String
    let priority: IssuePriority

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(Theme.priorityColor(priority)).frame(width: 6, height: 6).padding(.top, 5)
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 252, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
                .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
        )
    }
}
