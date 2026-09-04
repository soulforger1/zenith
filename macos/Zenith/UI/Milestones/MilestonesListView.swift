import SwiftUI
import ZenithData

/// Port of `app/(app)/spaces/[spaceSlug]/milestones/page.tsx` +
/// `milestone-card.tsx`, as a native `List` with context-menu actions
/// (right-click a row for rename/close/delete — the standard macOS
/// pattern) instead of always-visible icon buttons. Progress is always
/// computed on read from linked issues (never stored) — same as the TS
/// side.
struct MilestonesListView: View {
    @Environment(AppShellModel.self) private var shell
    let model: SpaceDetailModel

    @State private var isCreating = false

    var body: some View {
        Group {
            if model.milestones.isEmpty {
                ContentUnavailableView {
                    Label("No Milestones", systemImage: "flag")
                } description: {
                    Text("Create a milestone to group related tasks toward a goal.")
                }
            } else {
                List(model.milestones) { milestone in
                    MilestoneRow(model: model, milestone: milestone) {
                        shell.route = .milestoneDetail(model.space, milestone)
                    }
                }
            }
        }
        .navigationTitle("Milestones")
        .toolbar {
            ToolbarItem {
                Button {
                    isCreating = true
                } label: {
                    Label("New Milestone", systemImage: "plus")
                }
            }
        }
        .modalOverlay(isPresented: $isCreating) {
            MilestoneFormSheet(model: model, mode: .create(spaceId: model.space.id), onDismiss: { isCreating = false })
        }
    }
}

private struct MilestoneRow: View {
    let model: SpaceDetailModel
    let milestone: Milestone
    let onOpen: () -> Void

    @State private var isEditing = false

    private var linkedIssues: [Issue] {
        model.issues.filter { $0.milestoneId == milestone.id }
    }

    private var closedCount: Int {
        linkedIssues.filter(\.isClosed).count
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(milestone.title)
                        .font(.headline)
                        .strikethrough(milestone.isClosed)
                        .foregroundStyle(milestone.isClosed ? .secondary : .primary)
                    Spacer()
                    if let dueDate = milestone.dueDate {
                        Text("Due \(dueDate)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                MilestoneProgressBarView(closed: closedCount, total: linkedIssues.count)

                if !linkedIssues.isEmpty {
                    Text(linkedIssues.map(\.title).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .opacity(milestone.isClosed ? 0.6 : 1)
        .contextMenu {
            Button {
                Task { await model.toggleMilestoneClosed(milestone.id, isClosed: !milestone.isClosed) }
            } label: {
                Label(milestone.isClosed ? "Reopen" : "Close", systemImage: milestone.isClosed ? "arrow.uturn.backward" : "checkmark")
            }
            Button { isEditing = true } label: { Label("Edit", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) {
                Task { await model.deleteMilestone(milestone.id) }
            } label: { Label("Delete", systemImage: "trash") }
        }
        .modalOverlay(isPresented: $isEditing) {
            MilestoneFormSheet(model: model, mode: .edit(milestone), onDismiss: { isEditing = false })
        }
    }
}

struct MilestoneProgressBarView: View {
    let closed: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: Double(closed), total: Double(max(total, 1)))
                .progressViewStyle(.linear)
                .labelsHidden()
            Text("\(closed)/\(total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
