import Foundation

/// Port of `lib/actions/repos.ts`. `syncRepoContextAction` (the GitHub
/// fetch + AI summarize flow) lives in `ZenithAI`'s `AIOrchestration`
/// instead, since it depends on the `ZenithAI` package's `GitHubClient`/
/// `Prompts` — this file only owns the plain CRUD `repos` actions that
/// `ZenithData` can satisfy on its own.
public enum RepoActions {
    public struct RepoInput: Sendable {
        public var name: String
        public var url: String

        public init(name: String, url: String) {
            self.name = name
            self.url = url
        }

        func validate() throws -> (name: String, url: String) {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { throw ValidationError(field: "name", message: "Name is required") }
            guard trimmedName.count <= 50 else { throw ValidationError(field: "name", message: "Name is too long") }

            let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedUrl.isEmpty else { throw ValidationError(field: "url", message: "Repo URL is required") }
            guard trimmedUrl.count <= 300 else { throw ValidationError(field: "url", message: "Repo URL is too long") }
            _ = try GitHubURL.parse(trimmedUrl) // format check only, mirrors createRepoAction's parseRepoUrl guard

            return (trimmedName, trimmedUrl)
        }
    }

    public static func createRepo(_ db: ZenithDatabase, spaceId: UUID, _ input: RepoInput) async throws -> Repo {
        let (name, url) = try input.validate()
        return try await RepoQueries.createRepo(db, spaceId: spaceId, name: name, url: url)
    }

    public static func updateRepo(_ db: ZenithDatabase, id: UUID, name: String?, url: String?) async throws -> Repo? {
        var validatedName = name
        var validatedUrl = url
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ValidationError(field: "name", message: "Name is required") }
            guard trimmed.count <= 50 else { throw ValidationError(field: "name", message: "Name is too long") }
            validatedName = trimmed
        }
        if let url {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ValidationError(field: "url", message: "Repo URL is required") }
            guard trimmed.count <= 300 else { throw ValidationError(field: "url", message: "Repo URL is too long") }
            _ = try GitHubURL.parse(trimmed)
            validatedUrl = trimmed
        }
        return try await RepoQueries.updateRepo(db, id: id, name: validatedName, url: validatedUrl)
    }

    public static func deleteRepo(_ db: ZenithDatabase, id: UUID) async throws {
        try await RepoQueries.deleteRepo(db, id: id)
    }
}
