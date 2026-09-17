import Foundation
import GRDB

/// The app's local SQLite store — the single source of truth. Replaces the
/// former direct-Postgres connection pool of the same name; the `*Queries`
/// layer still takes a `ZenithDatabase` first argument and every call site
/// (~25 app files + `ZenithAI`) is unchanged.
///
/// A single `write { }` closure is a transaction (commit on return, roll
/// back on throw), replacing the old `withTransaction`.
public final class ZenithDatabase: Sendable {
    let writer: DatabaseWriter

    /// Opens (creating if needed) the on-disk store at `path` and runs any
    /// pending migrations. `path`'s parent directory must already exist.
    public init(path: URL) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: path.path, configuration: config)
        try zenithMigrator.migrate(pool)
        self.writer = pool
    }

    private init(writer: DatabaseWriter) {
        self.writer = writer
    }

    /// In-memory, fully-migrated store for tests and SwiftUI previews.
    public static func inMemory() throws -> ZenithDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        try zenithMigrator.migrate(queue)
        return ZenithDatabase(writer: queue)
    }

    /// No-op — kept so `AppEnvironment` / `ZenithAI` call sites don't churn.
    /// The local store needs no background run loop.
    public func start() {}

    public func shutdown() {
        try? writer.close()
    }

    public func ping() async throws {
        try await writer.read { _ in }
    }

    // MARK: - Internal query surface (used only by the `Queries` layer)

    func read<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await writer.read(block)
    }

    /// One `write` closure == one transaction.
    func write<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await writer.write(block)
    }
}
