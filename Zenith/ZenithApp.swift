import AppKit
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
    // App-wide transient feedback, injected alongside `shell` so the view
    // models (which own every CRUD path) can post success/error toasts.
    @State private var toasts = ToastCenter()
    @State private var hotkeyMonitor: OptionDoubleTapMonitor?
    @State private var shortcutMonitor: InAppShortcutMonitor?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(environment)
                .environment(shell)
                .environment(toasts)
                .task {
                    guard hotkeyMonitor == nil else { return }
                    let monitor = OptionDoubleTapMonitor(shell: shell)
                    monitor.start()
                    hotkeyMonitor = monitor

                    let shortcuts = InAppShortcutMonitor(shell: shell)
                    shortcuts.start()
                    shortcutMonitor = shortcuts
                }
                // If the user grants Accessibility in System Settings and
                // switches back, pick it up without a relaunch. `start()`
                // is a no-op when already running or still not permitted.
                .onReceive(
                    NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
                ) { _ in
                    hotkeyMonitor?.start()
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

                // No accelerator: paste-task's shortcut is a bare `c`
                // (see `InAppShortcutMonitor`), which can't be a menu key
                // equivalent without swallowing the letter everywhere.
                Button("Paste Task…") {
                    shell.openAiModal()
                }

                // The system-wide ⌥⌥ quick-capture gesture needs
                // Accessibility permission, which the app never prompts
                // for automatically (see `OptionDoubleTapMonitor.start`).
                // This is the explicit opt-in.
                Button("Enable ⌥⌥ Quick Capture…") {
                    hotkeyMonitor?.requestPermissionAndOpenSettings()
                }
            }
            CommandGroup(after: .toolbar) {
                Button("Search & Commands…") {
                    shell.openCommandPalette()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}
