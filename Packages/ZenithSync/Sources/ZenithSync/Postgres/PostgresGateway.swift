import Foundation
import Logging
import NIOSSL
import PostgresNIO

/// A short-lived connection to a remote Postgres database, used by the
/// one-time `PostgresImporter` (Phase 1) and the Postgres sync target
/// (Phase 2). Salvaged almost verbatim from the app's former
/// `ZenithDatabase` (which now names the *local* GRDB store) — same
/// `PostgresClient` pool, same TLS posture, same `SELECT 1` probe.
///
/// `PostgresClient` is a `Service`-shaped type that must be `run()` in a
/// long-lived task for its connection pool to process queries — `start()`
/// kicks that off once, and callers must `shutdown()` when done.
public actor PostgresGateway {
    private let client: PostgresClient
    private var runTask: Task<Void, Never>?
    public let logger: Logger

    public init(connectionString: String, logger: Logger = Logger(label: "com.zolboo.zenith.sync.postgres")) throws {
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
    /// right after construction.
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

    public func ping() async throws {
        _ = try await client.query("SELECT 1", logger: logger)
    }

    public func query(_ query: PostgresQuery) async throws -> PostgresRowSequence {
        try await client.query(query, logger: logger)
    }

    public func execute(_ query: PostgresQuery) async throws {
        _ = try await client.query(query, logger: logger)
    }

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
    /// the sync settings UI to validate a connection string before it's
    /// ever handed to a real gateway. Deliberately bypasses
    /// `PostgresClient`'s pool, whose circuit breaker masks the real
    /// failure reason once its retry budget is exhausted.
    public static func testConnection(
        connectionString: String, logger: Logger = Logger(label: "com.zolboo.zenith.sync.postgres.test")
    ) async throws {
        let parsed = try DatabaseURL.parse(connectionString)
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

    /// Encrypt, but don't verify the server's certificate against a trust
    /// store — matches `sslmode=require` (not `verify-full`), which is what
    /// the connection string implies and what hosts like Supabase's pooler
    /// (private CA, never validates against a public trust store) need.
    private static func clientTLSConfiguration() -> TLSConfiguration {
        var configuration = TLSConfiguration.makeClientConfiguration()
        configuration.certificateVerification = .none
        return configuration
    }
}
