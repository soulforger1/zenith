import Foundation

/// Persisted app preferences, stored as plain JSON at
/// `~/Library/Application Support/Zenith/config.json`. Local-first: the app
/// needs none of this to start (the local SQLite store just opens), so
/// every field is optional/defaulted and decoding is tolerant of a
/// pre-local-first `config.json` that only ever had a `databaseUrl` key.
public struct AppConfig: Codable, Sendable, Equatable {
    public enum StorageMode: String, Codable, Sendable {
        case local
    }

    public var storageMode: StorageMode
    public var sync: SyncSettings
    /// The connection string from the pre-local-first setup flow, if this
    /// `config.json` predates it. Used only to offer a one-time import into
    /// the local store on first launch after upgrading — never written back
    /// once read, so a fresh `config.json` never has this key.
    public var legacyDatabaseUrl: String?

    public init(storageMode: StorageMode = .local, sync: SyncSettings = SyncSettings(), legacyDatabaseUrl: String? = nil) {
        self.storageMode = storageMode
        self.sync = sync
        self.legacyDatabaseUrl = legacyDatabaseUrl
    }

    private enum CodingKeys: String, CodingKey {
        case storageMode, sync
        case legacyDatabaseUrl = "databaseUrl"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storageMode = try container.decodeIfPresent(StorageMode.self, forKey: .storageMode) ?? .local
        sync = try container.decodeIfPresent(SyncSettings.self, forKey: .sync) ?? SyncSettings()
        legacyDatabaseUrl = try container.decodeIfPresent(String.self, forKey: .legacyDatabaseUrl)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storageMode, forKey: .storageMode)
        try container.encode(sync, forKey: .sync)
        // `legacyDatabaseUrl` is intentionally never written back — once
        // read (import offered or skipped), config.json settles into the
        // new shape and drops the plaintext connection string.
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
    /// throwing.
    public static func load() -> AppConfig? {
        guard let url = try? configFileURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    public func save() throws {
        let url = try Self.configFileURL()
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}
