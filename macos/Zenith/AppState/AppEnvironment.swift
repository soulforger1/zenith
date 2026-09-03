import Foundation
import Observation
import ZenithData

/// Root app state: owns the `ZenithDatabase` connection once configured,
/// and drives the first-run setup flow. Replaces Electron's `main()`
/// sequencing (`electron/main.js`: read config -> maybe run setup window ->
/// start server) — here there's no server to spawn, just a DB connection to
/// open directly.
@Observable
@MainActor
public final class AppEnvironment {
    public private(set) var database: ZenithDatabase?
    public private(set) var isConfigured: Bool = false
    public private(set) var startupError: String?

    public init() {
        if let config = AppConfig.load() {
            Task { await configure(databaseUrl: config.databaseUrl) }
        }
    }

    /// Validates and opens the connection, then persists the config —
    /// mirrors `setup:submit`'s handler in `electron/main.js` (validate
    /// first, only write config.json on success).
    public func completeSetup(databaseUrl: String, githubToken: String?) async -> String? {
        let trimmedUrl = databaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty else { return "Database URL is required." }

        switch await AppConfig.validateDatabaseUrl(trimmedUrl) {
        case .failure(let error):
            return "Couldn't connect: \(error)"
        case .success:
            break
        }

        do {
            try AppConfig(databaseUrl: trimmedUrl).save()
        } catch {
            return "Couldn't save configuration: \(error)"
        }

        KeychainStore.setGithubToken(githubToken?.trimmingCharacters(in: .whitespacesAndNewlines))
        await configure(databaseUrl: trimmedUrl)
        return nil
    }

    private func configure(databaseUrl: String) async {
        do {
            let db = try ZenithDatabase(connectionString: databaseUrl)
            await db.start()
            database = db
            isConfigured = true
            startupError = nil
        } catch {
            startupError = error.diagnosticDescription
        }
    }
}
