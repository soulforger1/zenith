import SwiftUI

/// App entry point. Single window, no multi-window/document model needed —
/// this mirrors the Electron shell's single `BrowserWindow` (see
/// docs/native-rewrite-audit.md §1).
///
/// No custom window-chrome hacks here (an earlier version hid the titlebar
/// and manually repositioned the traffic lights to mimic the Electron
/// build pixel-for-pixel) — `NavigationSplitView`'s own sidebar already
/// gives the standard macOS "traffic lights float over the sidebar,
/// content extends under a translucent toolbar" look for free, matching
/// system apps like Mail/Notes/Music, which is exactly the native "glass"
/// appearance being asked for.
@main
struct ZenithApp: App {
    @State private var environment = AppEnvironment()
    // Owned here (not by `ContentView`) so the global hotkey monitor —
    // which lives entirely outside the view hierarchy — can be handed the
    // same instance the views react to via `.environment(shell)` below.
    @State private var shell = AppShellModel()
    @State private var hotkeyMonitor: OptionDoubleTapMonitor?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(environment)
                .environment(shell)
                .task {
                    guard hotkeyMonitor == nil else { return }
                    let monitor = OptionDoubleTapMonitor(shell: shell)
                    monitor.start()
                    hotkeyMonitor = monitor
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button("New Space") {
                    shell.route = .newSpace
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Paste Task…") {
                    shell.openAiModal()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }
    }
}
