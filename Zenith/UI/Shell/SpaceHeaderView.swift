import SwiftUI
import ZenithData

/// Port of `space-tabs.tsx`'s `SpaceHeader`, as native toolbar content
/// instead of a custom underlined tab bar — a segmented `Picker` is the
/// standard macOS way to switch between a small set of views (mirrors
/// Xcode's own editor/inspector switchers), and it comes with the
/// translucent toolbar material for free. The toolbar "+" ports
/// `space-tabs.tsx`'s `NewViewButton`; view rename/duplicate/delete (the
/// `ViewTabMenu` machinery) is still a follow-up slice.
struct SpaceHeaderView: ToolbarContent {
    @Environment(AppShellModel.self) private var shell
    let model: SpaceDetailModel
    /// Opens the "New view" modal — owned by the enclosing `SpaceDetailContainer`
    /// since `ToolbarContent` can't host a presentation modifier itself.
    let onNewView: () -> Void

    private enum Tag: Hashable {
        case view(UUID)
        case milestones
        case settings
    }

    private var selection: Binding<Tag?> {
        Binding(
            get: {
                switch shell.route {
                case .spaceView(_, let view): return .view(view.id)
                case .milestones: return .milestones
                case .settings: return .settings
                default: return nil
                }
            },
            set: { newTag in
                switch newTag {
                case .view(let id):
                    if let view = model.views.first(where: { $0.id == id }) {
                        shell.route = .spaceView(model.space, view)
                    }
                case .milestones:
                    shell.route = .milestones(model.space)
                case .settings:
                    shell.route = .settings(model.space)
                case nil:
                    break
                }
            }
        )
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: selection) {
                ForEach(model.views) { view in
                    Text(view.name).tag(Tag?.some(.view(view.id)))
                }
                Text("Milestones").tag(Tag?.some(.milestones))
                Text("Settings").tag(Tag?.some(.settings))
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 320)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: onNewView) {
                Image(systemName: "plus")
            }
            .help("New view")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                shell.openCommandPalette()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Search tasks (⌘K)")
        }
    }
}
