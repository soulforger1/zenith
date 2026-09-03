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
                // No bare-key shortcut here (the web build's un-modified
                // "c" convention doesn't translate safely — SwiftUI's
                // `.keyboardShortcut` has no equivalent of the web
                // listener's explicit "not currently typing" guard, so a
                // modifier-less letter shortcut would swallow that letter
                // out of every text field in the app). The real global
                // "open from anywhere" gesture is double-tap-Option
                // (`OptionDoubleTapMonitor`, ported from the Electron
                // build's own uiohook-based hotkey); ⌘⇧V covers it from the
                // menu bar for while the app is focused.
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
        }
    }
}
