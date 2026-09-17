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
    // The periodic sync loop's "something changed, reload" signal and the
    // coordinator that drives it — both constructible with no arguments so
    // they can be plain eager `@State` like the above; `syncCoordinator`
    // gets wired to the local store lazily once it exists (see the second
    // `.task` below), same shape `ContentView` uses for `spacesModel`.
    @State private var broadcaster = DataChangeBroadcaster()
    @State private var syncCoordinator = SyncCoordinator()
    @State private var hotkeyMonitor: OptionDoubleTapMonitor?
    @State private var shortcutMonitor: InAppShortcutMonitor?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(environment)
                .environment(shell)
                .environment(toasts)
                .environment(broadcaster)
                .environment(syncCoordinator)
                .task {
                    guard hotkeyMonitor == nil else { return }
                    let monitor = OptionDoubleTapMonitor(shell: shell)
                    monitor.start()
                    hotkeyMonitor = monitor

                    let shortcuts = InAppShortcutMonitor(shell: shell)
                    shortcuts.start()
                    shortcutMonitor = shortcuts
                }
                .task(id: environment.database == nil) {
                    guard let database = environment.database else { return }
                    syncCoordinator.configure(database: database, broadcaster: broadcaster, settings: environment.syncSettings)
                }
                // If the user grants Accessibility in System Settings and
                // switches back, pick it up without a relaunch. `start()`
                // is a no-op when already running or still not permitted.
                // Also a natural moment to catch up on sync — mirrors why
                // most apps sync on foreground, not just on a timer.
                .onReceive(
                    NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
                ) { _ in
                    hotkeyMonitor?.start()
                    syncCoordinator.onAppForeground()
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

                Button("Import from Postgres…") {
                    environment.presentPostgresImport()
                }
            }
            CommandGroup(after: .toolbar) {
                Button("Search & Commands…") {
                    shell.openCommandPalette()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }

        // macOS wires ⌘, to this automatically.
        Settings {
            SettingsRootView()
                .environment(environment)
                .environment(syncCoordinator)
        }
    }
}
