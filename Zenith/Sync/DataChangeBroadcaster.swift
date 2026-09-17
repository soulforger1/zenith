import Observation

/// Bumped whenever a sync round pulls changes that might affect what's on
/// screen. Container views observe `revision` and reload — the same "call
/// `load()` after a change" idiom every view model already uses for its
/// own local mutations, just triggered by a background pull instead of a
/// button tap. A coarse "something changed, reload" signal rather than
/// per-row `ValueObservation` — good enough for a periodic background sync
/// and much less machinery.
@Observable
@MainActor
public final class DataChangeBroadcaster {
    public private(set) var revision: Int = 0

    public init() {}

    public func bump() {
        revision &+= 1
    }
}
