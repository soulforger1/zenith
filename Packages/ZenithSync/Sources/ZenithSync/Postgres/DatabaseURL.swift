import Foundation

/// Parses a `postgres(ql)://user:pass@host:port/database?sslmode=...`
/// connection string (the shape both Supabase's pooled `DATABASE_URL` and
/// direct `DIRECT_URL` use — see `drizzle.config.ts`) into the pieces
/// `PostgresClient.Configuration` needs. PostgresNIO has no built-in URL
/// parser (that's normally a higher-level framework's job), so this is a
/// small dedicated one rather than pulling in a URL-parsing dependency for
/// a single call site.
public struct DatabaseURL: Sendable, Equatable {
    public let host: String
    public let port: Int
    public let username: String
    public let password: String?
    public let database: String
    /// True unless `sslmode=disable` is explicitly set — Supabase (and most
    /// hosted Postgres) requires TLS.
    public let requiresTLS: Bool

    public enum ParseError: Error, CustomStringConvertible {
        case invalidURL(String)
        case missingHost
        case missingDatabase

        public var description: String {
            switch self {
            case .invalidURL(let raw): return "\"\(raw)\" isn't a valid postgres connection URL."
            case .missingHost: return "Connection URL is missing a host."
            case .missingDatabase: return "Connection URL is missing a database name."
            }
        }
    }

    public static func parse(_ raw: String) throws -> DatabaseURL {
        guard let components = URLComponents(string: raw),
            let scheme = components.scheme,
            scheme == "postgres" || scheme == "postgresql"
        else {
            throw ParseError.invalidURL(raw)
        }
        guard let host = components.host, !host.isEmpty else { throw ParseError.missingHost }

        let database = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !database.isEmpty else { throw ParseError.missingDatabase }

        let sslMode = components.queryItems?.first(where: { $0.name == "sslmode" })?.value
        let requiresTLS = sslMode != "disable"

        return DatabaseURL(
            host: host,
            port: components.port ?? 5432,
            username: components.user?.removingPercentEncoding ?? components.user ?? "postgres",
            password: components.password?.removingPercentEncoding ?? components.password,
            database: database,
            requiresTLS: requiresTLS
        )
    }
}
