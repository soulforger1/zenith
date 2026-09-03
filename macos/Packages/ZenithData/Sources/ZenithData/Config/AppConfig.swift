import Foundation

/// Replaces Electron's `userData/config.json` (`electron/main.js`'s
/// `readConfig`/`writeConfig`) — the one-time setup flow's persisted state.
/// `databaseUrl` stays here in plain JSON (needed plaintext at startup
/// anyway, to construct `ZenithDatabase` before anything else can run);
/// `githubToken` is promoted to the macOS Keychain via `KeychainStore` — a
/// real security upgrade over the Electron version's plaintext file, and
/// trivial to do natively.
public struct AppConfig: Codable, Sendable, Equatable {
    public var databaseUrl: String

    public init(databaseUrl: String) {
        self.databaseUrl = databaseUrl
    }

    public static func configDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = base.appendingPathComponent("Zenith", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func configFileURL() throws -> URL {
        try configDirectory().appendingPathComponent("config.json")
    }

    /// Returns `nil` if no config exists yet (first run) rather than
    /// throwing — mirrors `readConfig`'s try/catch-to-null.
    public static func load() -> AppConfig? {
        guard let url = try? configFileURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    public func save() throws {
        let url = try Self.configFileURL()
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Real connectivity check, not just "is this a well-formed URL" — a
    /// typo'd password/host fails immediately here instead of surfacing
    /// later as a silently blank app. Mirrors `electron/main.js`'s
    /// `validateDatabaseUrl`.
    public struct ConnectivityError: Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    public static func validateDatabaseUrl(_ databaseUrl: String) async -> Result<Void, ConnectivityError> {
        do {
            try await ZenithDatabase.testConnection(connectionString: databaseUrl)
            return .success(())
        } catch {
            return .failure(ConnectivityError(message: error.diagnosticDescription))
        }
    }
}
