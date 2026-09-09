import Foundation
import Logging
import NIOSSL
import PostgresNIO

/// Owns the app's single Postgres connection pool for its lifetime —
/// direct replacement for Drizzle's `db` (`lib/db/index.ts`), which talks
/// straight to Postgres from the Next.js server process. No local backend
/// process sits between the app and the database; see
/// docs/native-rewrite-audit.md §6, decision 1.
///
/// `PostgresClient` is a `Service`-shaped type that must be `run()` in a
/// long-lived task for its connection pool to actually process queries —
/// `start()` kicks that off once, at app launch.
public actor ZenithDatabase {
    private let client: PostgresClient
    private var runTask: Task<Void, Never>?
    public let logger: Logger

    public init(connectionString: String, logger: Logger = Logger(label: "com.zolboo.zenith.db")) throws {
        let parsed = try DatabaseURL.parse(connectionString)
        let tls: PostgresClient.Configuration.TLS = parsed.requiresTLS ? .require(Self.clientTLSConfiguration()) : .disable
        let configuration = PostgresClient.Configuration(
            host: parsed.host,
            port: parsed.port,
            username: parsed.username,
            password: parsed.password,
            database: parsed.database,
            tls: tls
        )
        self.client = PostgresClient(configuration: configuration, backgroundLogger: logger)
        self.logger = logger
    }

    /// Starts the client's background connection-pool loop. Call once,
    /// right after construction (the app entry point does this at launch).
    public func start() {
        guard runTask == nil else { return }
        runTask = Task { [client] in
            await client.run()
        }
    }

    public func shutdown() {
        runTask?.cancel()
        runTask = nil
    }

    /// Real connectivity check, not just "is this a well-formed URL" — a
    /// typo'd password/host fails immediately here instead of surfacing
    /// later as a silently blank app. Mirrors `electron/main.js`'s
    /// `validateDatabaseUrl`.
    public func ping() async throws {
        _ = try await client.query("SELECT 1", logger: logger)
    }

    public func query(_ query: PostgresQuery) async throws -> PostgresRowSequence {
        try await client.query(query, logger: logger)
    }

    /// For statements whose result set doesn't matter (inserts/updates/
    /// deletes with no `RETURNING`).
    public func execute(_ query: PostgresQuery) async throws {
        _ = try await client.query(query, logger: logger)
    }

    /// Runs `body` against a single checked-out connection wrapped in a
    /// transaction, committing on success and rolling back if `body`
    /// throws — used wherever the TS side used `db.transaction(...)`
    /// (e.g. `IssueActions.updateFields`'s combined column-update +
    /// repo-link replace).
    public func withTransaction<T: Sendable>(_ body: @Sendable (PostgresConnection) async throws -> T) async throws -> T {
        try await client.withConnection { connection in
            try await connection.query("BEGIN", logger: self.logger)
            do {
                let result = try await body(connection)
                try await connection.query("COMMIT", logger: self.logger)
                return result
            } catch {
                _ = try? await connection.query("ROLLBACK", logger: self.logger)
                throw error
            }
        }
    }

    /// One-off connectivity check — opens a single `PostgresConnection`
    /// (no pool, no circuit breaker), runs `SELECT 1`, closes it. Used by
    /// the setup flow to validate a connection string *before* it's ever
    /// handed to a real `ZenithDatabase`. Deliberately bypasses
    /// `PostgresClient`'s pool: `ConnectionPool` wraps repeated connection
    /// failures behind a generic `connectionCreationCircuitBreakerTripped`
    /// once its retry budget is exhausted, which masks the real failure
    /// reason (bad password, wrong port, TLS mismatch) — useless for a
    /// first-time "does this string even work" check. Mirrors
    /// `electron/main.js`'s `validateDatabaseUrl`, which used a
    /// lightweight one-off `postgres()` client for the same reason, never
    /// the app's long-lived pool.
    public static func testConnection(
        connectionString: String, logger: Logger = Logger(label: "com.zolboo.zenith.db.test")
    ) async throws {
        let parsed = try DatabaseURL.parse(connectionString)
        // Unlike `PostgresClient.Configuration.TLS` (which takes a plain
        // `TLSConfiguration`), `PostgresConnection.Configuration.TLS`
        // wants an already-built `NIOSSLContext` — same posture as `init`
        // above, just wrapped differently.
        let tls: PostgresConnection.Configuration.TLS = parsed.requiresTLS
            ? .require(try NIOSSLContext(configuration: Self.clientTLSConfiguration()))
            : .disable
        let configuration = PostgresConnection.Configuration(
            host: parsed.host,
            port: parsed.port,
            username: parsed.username,
            password: parsed.password,
            database: parsed.database,
            tls: tls
        )
        let connection = try await PostgresConnection.connect(configuration: configuration, id: 0, logger: logger)
        do {
            _ = try await connection.query("SELECT 1", logger: logger)
        } catch {
            try? await connection.close()
            throw error
        }
        try await connection.close()
    }

    /// The TLS posture for every Postgres connection this app makes:
    /// encrypt, but don't verify the server's certificate against a trust
    /// store. This matches `sslmode=require` (not `verify-full`), which is
    /// what the connection string already implies (no `sslmode=` override
    /// requesting stricter verification) and what the existing Electron/
    /// Next.js app's `postgres` client actually does today.
    ///
    /// This isn't a shortcut taken for convenience — it's the correct
    /// match for hosts like Supabase's connection pooler, confirmed by
    /// inspecting the live TLS handshake directly (`openssl s_client
    /// -starttls postgres`): the pooler presents a chain rooted at
    /// Supabase's own private CA ("Supabase Root 2021 CA"), which is
    /// *never* going to validate against any public trust store — macOS's
    /// system roots included. `verify-full` would require distributing
    /// Supabase's specific root CA to the app and pinning to it, which is
    /// unnecessary for a personal single-user tool over what's already an
    /// encrypted connection.
    private static func clientTLSConfiguration() -> TLSConfiguration {
        var configuration = TLSConfiguration.makeClientConfiguration()
        configuration.certificateVerification = .none
        return configuration
    }
}
