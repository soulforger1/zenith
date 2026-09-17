import Foundation
import Observation
import ZenithData
import ZenithSync

/// Root app state: owns the local SQLite store for the app's lifetime.
/// Local-first — the store opens immediately with no configuration; the
/// only thing `AppEnvironment` still gates on is the (brief, in-process)
/// migration run. A pre-local-first `config.json` with a Postgres
/// connection string is detected and offered as a one-time import, but
/// nothing blocks on it.
@Observable
@MainActor
public final class AppEnvironment {
    public private(set) var database: ZenithDatabase?
    public private(set) var isConfigured: Bool = false
    public private(set) var startupError: String?

    /// Non-nil once, right after a fresh (empty) local store is opened and
    /// an old `config.json` still has a Postgres connection string on
    /// file — the trigger for `ImportFromPostgresView`'s first-run offer.
    /// Cleared once the user imports or dismisses it.
    public private(set) var pendingPostgresImportURL: String?

    /// The user's sync preferences (off by default) — the Settings → Sync
    /// pane reads/writes this via `saveSyncSettings`. `SyncCoordinator`
    /// gets its own copy at `configure(...)`/`updateSettings(...)` time
    /// rather than reading this live, so it isn't this class's job to push
    /// changes into the coordinator — the Settings pane does both.
    public private(set) var syncSettings: SyncSettings

    public init() {
        let config = AppConfig.load() ?? AppConfig()
        syncSettings = config.sync
        Task { await openLocalStore(legacyDatabaseUrl: config.legacyDatabaseUrl) }
    }

    private func openLocalStore(legacyDatabaseUrl: String?) async {
        do {
            let directory = try AppConfig.configDirectory()
            let storeURL = directory.appendingPathComponent("zenith.sqlite")
            let db = try ZenithDatabase(path: storeURL)
            database = db
            isConfigured = true
            startupError = nil

            if let legacyDatabaseUrl {
                let spaces = try await SpaceQueries.getSpaces(db)
                if spaces.isEmpty {
                    pendingPostgresImportURL = legacyDatabaseUrl
                }
            }
        } catch {
            startupError = error.diagnosticDescription
        }
    }

    /// Runs the one-time Postgres → local import, then clears the config's
    /// legacy connection string (moving it to Keychain, since it's now an
    /// opt-in sync credential rather than a plaintext startup requirement).
    /// Returns an error message on failure, `nil` on success.
    public func runPostgresImport(connectionString: String) async -> String? {
        guard let database else { return "Local database isn't ready yet." }
        let trimmed = connectionString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Database URL is required." }

        do {
            _ = try await PostgresImporter.run(connectionString: trimmed, into: database)
        } catch {
            return error.diagnosticDescription
        }

        KeychainStore.setPostgresConnectionString(trimmed)
        var config = AppConfig.load() ?? AppConfig()
        config.legacyDatabaseUrl = nil
        try? config.save()
        pendingPostgresImportURL = nil
        return nil
    }

    /// Dismisses the first-run import offer without importing anything —
    /// the connection string stays in `config.json` (untouched) so
    /// Settings → Sync (Phase 2) can still offer it later.
    public func dismissPostgresImportOffer() {
        pendingPostgresImportURL = nil
    }

    /// Manual re-trigger for the import sheet (the app menu's "Import from
    /// Postgres…" command) — prefills from Keychain if a connection string
    /// was saved by a previous import, empty otherwise.
    public func presentPostgresImport() {
        pendingPostgresImportURL = KeychainStore.postgresConnectionString() ?? ""
    }

    /// Persists new sync preferences to `config.json`. Doesn't itself
    /// notify `SyncCoordinator` — callers (the Settings → Sync pane) call
    /// `SyncCoordinator.updateSettings(_:)` alongside this.
    public func saveSyncSettings(_ newSettings: SyncSettings) {
        syncSettings = newSettings
        var config = AppConfig.load() ?? AppConfig()
        config.sync = newSettings
        try? config.save()
    }
}
