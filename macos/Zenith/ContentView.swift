import SwiftUI
import ZenithData

/// Root view: shows the first-run `SetupView` until a database connection
/// is configured (mirrors `electron/main.js`'s "no config -> setup window,
/// else -> main window" branch), then the app shell — a standard
/// `NavigationSplitView` (sidebar + detail), which is what gives this app
/// its native macOS chrome (translucent sidebar, traffic lights sitting
/// over it, standard toolbar) with no custom window hacks needed.
struct ContentView: View {
    @Environment(AppEnvironment.self) private var environment
    // Owned by `ZenithApp` (not here) so the global double-tap-Option
    // hotkey monitor, which lives outside the view hierarchy entirely, can
    // share the same instance.
    @Environment(AppShellModel.self) private var shell
    @State private var spacesModel: SpacesListModel?
    @State private var spaceDetailModels: [UUID: SpaceDetailModel] = [:]

    var body: some View {
        Group {
            if let database = environment.database, let spacesModel {
                NavigationSplitView {
                    AppSidebar(summaries: spacesModel.summaries) {
                        shell.route = .newSpace
                    }
                } detail: {
                    detailContent(spacesModel: spacesModel)
                }
                .navigationSplitViewStyle(.balanced)
                // Populating `spaceDetailModels` has to happen here, not
                // inline inside `detailContent`'s @ViewBuilder switch —
                // mutating @State from within a view-tree-construction
                // pass is undefined behavior in SwiftUI (confirmed the
                // hard way: it silently dropped the write, so every
                // render created a fresh, never-`load()`ed
                // `SpaceDetailModel` instead of reusing the loaded one).
                // `.onChange` runs as a side effect in response to state
                // changes, which is the legitimate place for this.
                .onChange(of: shell.route, initial: true) { _, newRoute in
                    ensureDetailModel(for: newRoute.space, database: database)
                }
                // Same rule as the route-driven `onChange` above: the AI
                // modal's target space is resolved and its detail model
                // ensured *before* presentation, as a side effect — never
                // inline inside the sheet's own view-builder closure.
                .onChange(of: shell.isAiModalPresented, initial: false) { _, isPresented in
                    guard isPresented else { return }
                    ensureDetailModel(
                        for: shell.route.space ?? spacesModel.summaries.first?.space, database: database)
                }
                // The task detail inspector's target space is always the
                // one whose Table/Board is currently on screen (that's the
                // only place `shell.openTask` is ever called from), so its
                // `SpaceDetailModel` is already guaranteed to exist by the
                // route-driven `onChange` above — no separate ensure step
                // needed here, unlike the AI modal's own space fallback.
                .inspector(isPresented: Binding(
                    get: { shell.taskDetailTarget != nil },
                    set: { if !$0 { shell.closeTask() } }
                )) {
                    if let target = shell.taskDetailTarget, let model = spaceDetailModels[target.spaceId] {
                        TaskDetailView(model: model, issueId: target.issueId)
                            .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
                    } else {
                        ProgressView()
                    }
                }
                .sheet(isPresented: Binding(get: { shell.isAiModalPresented }, set: { shell.isAiModalPresented = $0 })) {
                    // Targets whichever space is currently open, falling
                    // back to the first space in the sidebar — mirrors the
                    // web modal's `spaces.find(activeSlug) ?? spaces[0]`.
                    if let target = shell.route.space ?? spacesModel.summaries.first?.space,
                        let model = spaceDetailModels[target.id]
                    {
                        PasteTaskModal(model: model) { shell.isAiModalPresented = false }
                    } else {
                        ContentUnavailableView("Create a space first", systemImage: "sparkles")
                            .frame(width: 360, height: 200)
                    }
                }
            } else if environment.isConfigured {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SetupView()
            }
        }
        .task(id: environment.database == nil) {
            if let database = environment.database, spacesModel == nil {
                spacesModel = SpacesListModel(database: database)
            }
        }
    }

    private func ensureDetailModel(for space: Space?, database: ZenithDatabase) {
        guard let space, spaceDetailModels[space.id] == nil else { return }
        spaceDetailModels[space.id] = SpaceDetailModel(space: space, database: database)
    }

    /// Read-only lookup — never creates or mutates. `ensureDetailModel`
    /// (called from `.onChange`, not from here) is the only writer.
    @ViewBuilder
    private func detailContent(spacesModel: SpacesListModel) -> some View {
        switch shell.route {
        case .dashboard:
            SpacesDashboardView(model: spacesModel)
        case .newSpace:
            NewSpaceView(model: spacesModel)
        case .space(let space):
            if let model = spaceDetailModels[space.id] {
                SpaceLandingView(model: model)
            } else {
                ProgressView()
            }
        case .spaceView(let space, let view):
            detailContainer(for: space) { model in
                ViewContentView(model: model, view: view)
            }
        case .milestones(let space):
            detailContainer(for: space) { model in
                MilestonesListView(model: model)
            }
        case .milestoneDetail(let space, let milestone):
            detailContainer(for: space) { model in
                MilestoneDetailView(model: model, milestone: milestone)
            }
        case .settings(let space):
            detailContainer(for: space) { model in
                SettingsView(model: model)
            }
        }
    }

    @ViewBuilder
    private func detailContainer<Content: View>(
        for space: Space, @ViewBuilder content: (SpaceDetailModel) -> Content
    ) -> some View {
        if let model = spaceDetailModels[space.id] {
            SpaceDetailContainer(model: model) { content(model) }
        } else {
            ProgressView()
        }
    }
}

/// Resolves a bare space route to its default view once views have
/// loaded — mirrors `/spaces/[slug]`'s server-side redirect.
private struct SpaceLandingView: View {
    @Environment(AppShellModel.self) private var shell
    let model: SpaceDetailModel

    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                await model.load()
                if let defaultView = model.defaultView {
                    shell.route = .spaceView(model.space, defaultView)
                }
            }
    }
}

/// Wraps every per-space screen with the shared header/tab bar (port of
/// `app/(app)/spaces/[spaceSlug]/layout.tsx` + `SpaceHeader`).
private struct SpaceDetailContainer<Content: View>: View {
    let model: SpaceDetailModel
    @ViewBuilder let content: Content

    var body: some View {
        Group {
            if model.isLoading && model.views.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .navigationTitle(model.space.name)
        .toolbar {
            SpaceHeaderView(model: model)
        }
        .task { if model.views.isEmpty { await model.load() } }
    }
}

@ViewBuilder
private func ViewContentView(model: SpaceDetailModel, view: ZView) -> some View {
    switch view.type {
    case .table:
        IssueTableView(model: model)
    case .board:
        KanbanBoardView(model: model, view: view)
    case .roadmap:
        RoadmapView(model: model, view: view)
    }
}
