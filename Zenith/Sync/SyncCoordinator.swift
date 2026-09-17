import Foundation
import Observation
import ZenithData
import ZenithSync

/// Drives the app's periodic, opt-in sync loop. Owned by `ZenithApp`
/// alongside `AppEnvironment`, constructed with no arguments (so it can be
/// a plain eager `@State`, like `environment`/`shell`/`toasts`) and wired
/// up once the local store exists via `configure(...)` — the same
/// lazy-initialization shape `ContentView` already uses for `spacesModel`.
///
/// Modeled on the old direct-Postgres `ZenithDatabase.start()`'s
/// long-lived `runTask` for the interval loop shape, plus an
/// app-foreground trigger and a manual "Sync Now" entry point.
@Observable
@MainActor
public final class SyncCoordinator {
    public enum Status: Sendable, Equatable {
        case idle
        case syncing
        case error(String)
    }

    public private(set) var status: Status = .idle
    public private(set) var lastSyncedAt: Date?

    private var database: ZenithDatabase?
    private var broadcaster: DataChangeBroadcaster?
    private var settings: SyncSettings = SyncSettings()
    private var loopTask: Task<Void, Never>?
    private var lastRunAt: Date?

    public init() {}

    /// Wires the coordinator to a live local store — called once from
    /// `ZenithApp` as soon as `AppEnvironment.database` exists.
    public func configure(database: ZenithDatabase, broadcaster: DataChangeBroadcaster, settings: SyncSettings) {
        self.database = database
        self.broadcaster = broadcaster
        self.settings = settings
        restart()
    }

    /// Called by the Settings → Sync pane whenever the user changes a
    /// toggle or the interval — restarts the loop with the new settings
    /// (a disabled target stops immediately; a newly-enabled one starts).
    public func updateSettings(_ newSettings: SyncSettings) {
        settings = newSettings
        restart()
    }

    public func start() {
        guard loopTask == nil, database != nil, anyTargetEnabled else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let seconds = self.intervalSeconds()
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// Manual "Sync Now" — runs immediately regardless of the interval.
    public func syncNow() async {
        await tick()
    }

    /// Called on `NSApplication.didBecomeActiveNotification`, alongside
    /// the existing hotkey-monitor re-`start()` in `ZenithApp`. Debounced
    /// so switching apps repeatedly doesn't hammer the target.
    public func onAppForeground() {
        guard database != nil, anyTargetEnabled else { return }
        if let lastRunAt, Date().timeIntervalSince(lastRunAt) < 60 { return }
        Task { await tick() }
    }

    private var anyTargetEnabled: Bool {
        settings.postgresEnabled
    }

    private func restart() {
        stop()
        start()
    }

    private func intervalSeconds() -> Double {
        max(60, Double(settings.intervalMinutes) * 60)
    }

    private func tick() async {
        guard let database, anyTargetEnabled else { return }
        guard status != .syncing else { return }
        status = .syncing
        defer { lastRunAt = Date() }

        var targets: [any SyncTarget] = []
        if settings.postgresEnabled, let connectionString = KeychainStore.postgresConnectionString() {
            targets.append(PostgresSyncTarget(connectionString: connectionString))
        }
        guard !targets.isEmpty else {
            status = .idle
            return
        }

        var anyPulled = false
        var firstError: String?
        for target in targets {
            do {
                let outcome = try await SyncReconciler.runRound(store: database, target: target)
                anyPulled = anyPulled || outcome.pulled > 0
            } catch {
                firstError = firstError ?? error.diagnosticDescription
            }
        }

        if anyPulled { broadcaster?.bump() }
        lastSyncedAt = Date()
        status = firstError.map(Status.error) ?? .idle
    }
}
