import ZenithData

/// Which content the shell's detail pane shows — the native equivalent of
/// Next.js's `app/(app)/**` route tree, collapsed into an in-memory enum
/// since there's no URL bar to drive navigation from.
enum ShellRoute: Equatable {
    case dashboard
    case newSpace
    /// Bare space link — resolves to `spaceView(space, defaultView)` once
    /// the space's views have loaded, mirroring `/spaces/[slug]`'s
    /// redirect-to-default-view behavior.
    case space(Space)
    case spaceView(Space, ZView)
    case milestones(Space)
    case milestoneDetail(Space, Milestone)
    case settings(Space)

    static func == (lhs: ShellRoute, rhs: ShellRoute) -> Bool {
        switch (lhs, rhs) {
        case (.dashboard, .dashboard), (.newSpace, .newSpace): return true
        case (.space(let a), .space(let b)): return a.id == b.id
        case (.spaceView(let sa, let va), .spaceView(let sb, let vb)): return sa.id == sb.id && va.id == vb.id
        case (.milestones(let a), .milestones(let b)): return a.id == b.id
        case (.milestoneDetail(let sa, let ma), .milestoneDetail(let sb, let mb)): return sa.id == sb.id && ma.id == mb.id
        case (.settings(let a), .settings(let b)): return a.id == b.id
        default: return false
        }
    }

    var space: Space? {
        switch self {
        case .dashboard, .newSpace: return nil
        case .space(let space), .spaceView(let space, _), .milestones(let space), .settings(let space): return space
        case .milestoneDetail(let space, _): return space
        }
    }
}
