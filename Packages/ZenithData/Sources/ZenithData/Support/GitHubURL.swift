import Foundation

/// Port of `parseRepoUrl` from `lib/github/client.ts`. Pure string parsing
/// (no network call), so it lives here rather than in `ZenithAI` — both
/// `RepoActions` (URL-format validation on create/update) and `ZenithAI`'s
/// `GitHubClient` (actually fetching the repo) need it.
public enum GitHubURL {
    public struct Parsed: Sendable, Equatable {
        public let owner: String
        public let repo: String
    }

    /// Accepts "https://github.com/owner/repo", "github.com/owner/repo", or
    /// bare "owner/repo".
    public static func parse(_ input: String) throws -> Parsed {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(".git") { trimmed.removeLast(4) }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }

        var withoutHost = trimmed
        for prefix in ["https://", "http://"] {
            if withoutHost.hasPrefix(prefix) { withoutHost.removeFirst(prefix.count) }
        }
        if withoutHost.hasPrefix("github.com/") { withoutHost.removeFirst("github.com/".count) }

        let parts = withoutHost.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
            !parts[0].contains(where: \.isWhitespace), !parts[1].contains(where: \.isWhitespace)
        else {
            throw ValidationError(field: "url", message: "\"\(input)\" doesn't look like a GitHub repo — use \"owner/repo\" or a github.com URL.")
        }
        return Parsed(owner: String(parts[0]), repo: String(parts[1]))
    }
}
