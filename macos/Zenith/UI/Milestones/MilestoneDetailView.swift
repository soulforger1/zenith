import SwiftUI
import ZenithData

/// Port of `app/(app)/spaces/[spaceSlug]/milestones/[milestoneId]/page.tsx`
/// — progress bar, close/reopen, edit, flat list of linked issues, as a
/// native `List` + toolbar instead of a hand-styled scroll view.
struct MilestoneDetailView: View {
    let model: SpaceDetailModel
    let milestone: Milestone

    @Environment(AppShellModel.self) private var shell
    @State private var isEditing = false

    private var linkedIssues: [Issue] {
        model.issues.filter { $0.milestoneId == milestone.id }
    }

    private var currentMilestone: Milestone {
        model.milestones.first { $0.id == milestone.id } ?? milestone
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if let description = currentMilestone.description {
                        Text(description).foregroundStyle(.secondary)
                    }
                    MilestoneProgressBarView(
                        closed: linkedIssues.filter(\.isClosed).count, total: linkedIssues.count)
                }
            }

            Section("Linked Tasks") {
                if linkedIssues.isEmpty {
                    Text("No tasks linked to this milestone yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(linkedIssues) { issue in
                        Button {
                            shell.openTask(spaceId: model.space.id, issueId: issue.id)
                        } label: {
                            LabeledContent {
                                Text(statusLabel(issue.status)).font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label {
                                    Text(issue.title)
                                } icon: {
                                    Circle().fill(Theme.priorityColor(issue.priority)).frame(
                                        width: 6, height: 6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(currentMilestone.title)
        .toolbar {
            if currentMilestone.isClosed {
                ToolbarItem(placement: .principal) {
                    Text("CLOSED").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            ToolbarItem {
                Button {
                    Task {
                        await model.toggleMilestoneClosed(
                            currentMilestone.id, isClosed: !currentMilestone.isClosed)
                    }
                } label: {
                    Label(
                        currentMilestone.isClosed ? "Reopen" : "Close",
                        systemImage: currentMilestone.isClosed
                            ? "arrow.uturn.backward" : "checkmark"
                    )
                }
            }
            ToolbarItem {
                Button {
                    isEditing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            MilestoneFormSheet(
                model: model, mode: .edit(currentMilestone), onDismiss: { isEditing = false })
        }
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
