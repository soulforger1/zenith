import Foundation
import ZenithData

/// Port of `lib/github/client.ts`. Curated (not exhaustive) signals used to
/// seed the AI repo-summary prompt — capped so a "Sync" stays a small,
/// bounded one-off cost, never a full source dump.
public enum GitHubClient {
    private static let readmeCharLimit = 6000
    private static let packageJsonCharLimit = 2000
    private static let treeEntryLimit = 60

    public struct RepoSnapshot: Sendable, Equatable {
        public var fullName: String
        public var description: String?
        public var language: String?
        public var topics: [String]
        public var readme: String?
        public var packageJson: String?
        public var tree: [String]
    }

    public enum GitHubError: Error, CustomStringConvertible {
        case notFound(owner: String, repo: String)
        case rateLimited
        case apiError(status: Int, owner: String, repo: String)

        public var description: String {
            switch self {
            case .notFound(let owner, let repo):
                return "GitHub repo \"\(owner)/\(repo)\" not found or private — add a GitHub token for private repos."
            case .rateLimited:
                return "GitHub rate limit hit — try again later, or add a GitHub token to raise the limit."
            case .apiError(let status, let owner, let repo):
                return "GitHub API error (\(status)) fetching \(owner)/\(repo)."
            }
        }
    }

    private static func request(_ path: String, token: String?, accept: String = "application/vnd.github+json") -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com\(path)")!)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// Fetches a raw file's contents; returns `nil` on 404 or any other
    /// non-2xx response — callers treat a missing file as "skip it", not a
    /// hard failure.
    private static func fetchRawOrNil(_ path: String, token: String?) async -> String? {
        guard let (data, response) = try? await URLSession.shared.data(for: request(path, token: token, accept: "application/vnd.github.raw")),
            let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Curated snapshot of a repo (metadata + README + package.json +
    /// top-level file names) — the input to a one-off AI summarization, not
    /// a live context source. Never called per task-parse, only from a
    /// manual "Sync".
    public static func getRepoSnapshot(repoUrl: String, githubToken: String?) async throws -> RepoSnapshot {
        let parsed = try GitHubURL.parse(repoUrl)
        let base = "/repos/\(parsed.owner)/\(parsed.repo)"

        let (metaData, metaResponse) = try await URLSession.shared.data(for: request(base, token: githubToken))
        guard let http = metaResponse as? HTTPURLResponse else {
            throw GitHubError.apiError(status: 0, owner: parsed.owner, repo: parsed.repo)
        }
        if http.statusCode == 404 { throw GitHubError.notFound(owner: parsed.owner, repo: parsed.repo) }
        if http.statusCode == 403 { throw GitHubError.rateLimited }
        guard (200...299).contains(http.statusCode) else {
            throw GitHubError.apiError(status: http.statusCode, owner: parsed.owner, repo: parsed.repo)
        }
        let meta = (try? JSONSerialization.jsonObject(with: metaData) as? [String: Any]) ?? [:]

        async let readmeTask = fetchRawOrNil("\(base)/readme", token: githubToken)
        async let packageJsonTask = fetchRawOrNil("\(base)/contents/package.json", token: githubToken)
        let (readme, packageJson) = await (readmeTask, packageJsonTask)

        var tree: [String] = []
        if let (treeData, treeResponse) = try? await URLSession.shared.data(for: request("\(base)/contents", token: githubToken)),
            let treeHTTP = treeResponse as? HTTPURLResponse, (200...299).contains(treeHTTP.statusCode),
            let entries = try? JSONSerialization.jsonObject(with: treeData) as? [[String: Any]]
        {
            tree = entries.prefix(treeEntryLimit).compactMap { entry in
                guard let name = entry["name"] as? String else { return nil }
                let type = entry["type"] as? String
                return type == "dir" ? "\(name)/" : name
            }
        }

        return RepoSnapshot(
            fullName: (meta["full_name"] as? String) ?? "\(parsed.owner)/\(parsed.repo)",
            description: meta["description"] as? String,
            language: meta["language"] as? String,
            topics: (meta["topics"] as? [String]) ?? [],
            readme: readme.map { String($0.prefix(readmeCharLimit)) },
            packageJson: packageJson.map { String($0.prefix(packageJsonCharLimit)) },
            tree: tree
        )
    }
}
