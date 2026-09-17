/// The result of one `SyncReconciler.runRound` call.
public struct SyncOutcome: Sendable, Equatable {
    public let pulled: Int
    public let pushed: Int

    public init(pulled: Int, pushed: Int) {
        self.pulled = pulled
        self.pushed = pushed
    }
}
