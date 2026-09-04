import SwiftUI
import ZenithData

/// Port of `components/layout/command-palette.tsx`. A Spotlight-style command
/// list: jump to Milestones/Settings in the active space, switch spaces, or
/// open the paste-task modal. Filter by typing; ↑/↓ to move, ⏎ to run, Esc
/// to close. Opened from the ⌘K menu command, the toolbar magnifier, and the
/// sidebar's bottom "Search & commands" button (all route through
/// `AppShellModel.openCommandPalette`).
struct CommandPaletteView: View {
    @Environment(AppShellModel.self) private var shell

    let summaries: [SpacesListModel.SpaceSummary]
    let activeSpace: Space?
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    struct Command: Identifiable {
        let id: String
        let systemImage: String
        let title: String
        let perform: () -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Type a command or search…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(16)
                .focused($fieldFocused)
                .onChange(of: query) { _, _ in selection = 0 }
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                .onKeyPress(.return) { runSelected(); return .handled }
                .onKeyPress(.escape) { onDismiss(); return .handled }

            Divider()

            if filtered.isEmpty {
                Text("No matches.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, command in
                                CommandRow(command: command, isSelected: index == selection)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { run(command) }
                                    .onHover { if $0 { selection = index } }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selection) { _, new in
                        proxy.scrollTo(new, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        // A bare `.onAppear` focus set is dropped often enough when the view
        // is mounted inside a freshly-presented overlay; a turn of the run
        // loop makes it stick.
        .task {
            try? await Task.sleep(for: .milliseconds(40))
            fieldFocused = true
        }
    }

    private var commands: [Command] {
        var items: [Command] = []
        if let activeSpace {
            items.append(Command(id: "goto-milestones", systemImage: "flag", title: "Go to Milestones") {
                shell.route = .milestones(activeSpace)
            })
            items.append(Command(id: "goto-settings", systemImage: "gearshape", title: "Go to Settings") {
                shell.route = .settings(activeSpace)
            })
        }
        for summary in summaries {
            items.append(Command(id: "space-\(summary.id)", systemImage: "folder", title: "Switch to \(summary.space.name)") {
                shell.route = .space(summary.space)
            })
        }
        items.append(Command(id: "paste-task", systemImage: "sparkles", title: "Paste from manager…") {
            shell.openAiModal()
        })
        return items
    }

    private var filtered: [Command] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return commands }
        return commands.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private func moveSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        selection = (selection + delta + filtered.count) % filtered.count
    }

    private func runSelected() {
        guard filtered.indices.contains(selection) else { return }
        run(filtered[selection])
    }

    private func run(_ command: Command) {
        // Close the palette first so its dismiss animation doesn't race a
        // command that presents another overlay (e.g. the paste-task modal).
        onDismiss()
        command.perform()
    }
}

private struct CommandRow: View {
    let command: CommandPaletteView.Command
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.systemImage)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 18)
            Text(command.title)
                .foregroundStyle(isSelected ? .white : .primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }
}
