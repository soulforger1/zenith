import SwiftUI

/// The app's Settings window (⌘,) — currently just Sync; room to grow with
/// a General pane etc. later without disrupting this shell.
struct SettingsRootView: View {
    var body: some View {
        TabView {
            SyncSettingsPane()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 480)
        .scenePadding()
    }
}

#Preview {
    SettingsRootView()
        .environment(AppEnvironment())
        .environment(SyncCoordinator())
}
