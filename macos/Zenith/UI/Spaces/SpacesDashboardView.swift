import SwiftUI
import ZenithData

/// Port of `app/(app)/spaces/page.tsx` — grid of space cards (open/total
/// issue counts) + an "Upcoming" widget (issues due in the next 7 days
/// across all spaces). Empty state prompts to create a space.
struct SpacesDashboardView: View {
    @Environment(AppShellModel.self) private var shell
    let model: SpacesListModel

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if model.isLoading && model.summaries.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if model.summaries.isEmpty {
                    ContentUnavailableView {
                        Label("No spaces yet", systemImage: "square.stack.3d.up.slash")
                    } description: {
                        Text("Create a space to start tracking tasks for a project.")
                    } actions: {
                        Button("Create your first space") { shell.route = .newSpace }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.summaries) { summary in
                            SpaceCard(summary: summary) {
                                shell.route = .space(summary.space)
                            }
                        }
                    }
                }

                if !model.upcoming.isEmpty {
                    upcomingSection
                }

                if let error = model.loadError {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            }
            .padding(20)
        }
        .navigationTitle("Spaces")
        .toolbar {
            ToolbarItem {
                Button {
                    shell.route = .newSpace
                } label: {
                    Label("New space", systemImage: "plus")
                }
                .help("New space")
            }
        }
        .task { await model.load() }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(model.upcoming) { issue in
                    // Plain HStack instead of `LabeledContent` — with a
                    // long, wrapping title, `LabeledContent`'s label slot
                    // centered the wrapped text instead of keeping it
                    // left-aligned; a manual layout gives full control.
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Theme.priorityColor(issue.priority)).frame(width: 6, height: 6).padding(.top, 6)
                        Text(issue.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            Text(issue.spaceName).foregroundStyle(.secondary)
                            if let dueDate = issue.dueDate {
                                Text(dueDate).foregroundStyle(.secondary).monospaced()
                            }
                        }
                        .font(.caption)
                        .fixedSize()
                    }
                    .padding(.vertical, 6)
                    if issue.id != model.upcoming.last?.id { Divider() }
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct SpaceCard: View {
    let summary: SpacesListModel.SpaceSummary
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                Text(summary.space.name)
                    .font(.headline)
                if let description = summary.space.description {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Text("\(summary.openCount) open").monospacedDigit()
                    Text("·")
                    Text("\(summary.totalCount) total").monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(height: 110, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
