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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(environment)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            SidebarCommands()
        }
    }
}
