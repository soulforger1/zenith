import SwiftUI
import ZenithData

/// Port of `components/layout/app-sidebar.tsx` as a native `List` —
/// `.listStyle(.sidebar)` gives the standard translucent macOS sidebar
/// material, native row-selection highlighting, and automatic
/// collapse/expand (wired to the app's "Show/Hide Sidebar" menu command
/// via `SidebarCommands()` in `ZenithApp`) for free, replacing the
/// hand-rolled collapsible `VStack` this used to be.
struct AppSidebar: View {
    @Environment(AppShellModel.self) private var shell

    let summaries: [SpacesListModel.SpaceSummary]
    let onNewSpace: () -> Void

    private var selection: Binding<UUID?> {
        Binding(
            get: { shell.route.space?.id },
            set: { newId in
                guard let newId, let summary = summaries.first(where: { $0.id == newId }) else { return }
                shell.route = .space(summary.space)
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section {
                Button {
                    shell.openAiModal()
                } label: {
                    Label("Paste task", systemImage: "sparkles")
                }
                .help("Turn pasted text or a screenshot into a task (press C, or double-tap ⌥)")
                // Bare-key "c" (matching the web build) is handled by
                // `InAppShortcutMonitor` — a local `NSEvent` monitor with
                // the "not currently typing" guard SwiftUI's
                // `.keyboardShortcut` can't express. Double-tap-Option
                // (`OptionDoubleTapMonitor`) is the system-wide
                // open-from-anywhere gesture.
            }

            Section("Spaces") {
                if summaries.isEmpty {
                    Text("No spaces yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summaries) { summary in
                        Label(summary.space.name, systemImage: "folder")
                            .badge(summary.totalCount)
                            .tag(summary.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Zenith")
        .toolbar {
            ToolbarItem {
                Button(action: onNewSpace) {
                    Image(systemName: "plus")
                }
                .help("New space")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                shell.openCommandPalette()
            } label: {
                Label("Search & commands", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(10)
            .background(.regularMaterial)
            .help("Search tasks and run commands (⌘K)")
        }
    }
}
