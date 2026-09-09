import Foundation
import ZenithData

/// Ports the actual `app/api/ai/*/route.ts` handler logic (parallel context
/// fetch → prompt call → name/field resolution → assembled result) — that
/// glue is real logic, not boilerplate, so subtask 4's AI modal should call
/// one function per flow here rather than re-implementing the
/// orchestration in a view model.
public enum AIOrchestration {
    public struct ResolvedTask: Sendable {
        public let task: ParsedTask
        public let repoIds: [UUID]
        public let milestoneId: UUID?
        public let customFieldValues: [String: AnyCodableValue]
    }

    private static func optionLabels(_ field: CustomField) -> [String] {
        switch field.type {
        case .singleSelect, .multiSelect: return field.options.fieldOptions.map(\.name)
        case .iteration: return field.options.iterationOptions.map(\.title)
        case .text, .number, .date: return []
        }
    }

    private struct SpaceContext {
        let spaceContext: String?
        let images: [AttachedImage]
        let repos: [Repo]
        let milestones: [Milestone]
        let customFields: [CustomField]
    }

    private static func fetchSpaceContext(_ db: ZenithDatabase, spaceId: UUID, includeImages: Bool) async throws -> SpaceContext {
        async let space = SpaceQueries.getSpaceById(db, id: spaceId)
        async let images = includeImages ? SpaceImageQueries.getSpaceImages(db, spaceId: spaceId) : []
        async let repos = RepoQueries.getReposForSpace(db, spaceId: spaceId)
        async let milestones = MilestoneQueries.getMilestonesForSpace(db, spaceId: spaceId)
        async let customFields = CustomFieldQueries.getCustomFieldsForSpace(db, spaceId: spaceId)

        let (spaceValue, imagesValue, reposValue, milestonesValue, fieldsValue) =
            try await (space, images, repos, milestones, customFields)

        let attachedImages: [AttachedImage] = imagesValue.compactMap { image in
            guard let parsed = DataURL.parse(image.dataUrl) else { return nil }
            return AttachedImage(mimeType: parsed.mimeType, data: parsed.data)
        }

        return SpaceContext(
            spaceContext: spaceValue?.context, images: attachedImages, repos: reposValue,
            milestones: milestonesValue, customFields: fieldsValue
        )
    }

    private static func resolveTask(
        _ db: ZenithDatabase, spaceId: UUID?, task: ParsedTask, repos: [Repo], milestones: [Milestone], customFields: [CustomField]
    ) async throws -> ResolvedTask {
        let repoIds = NameMatch.resolveIds(task.repos, items: repos.map { (id: $0.id, name: $0.name) })
        let milestoneId = NameMatch.resolveId(task.milestone, items: milestones.map { (id: $0.id, name: $0.title) })

        var customFieldValues: [String: AnyCodableValue] = [:]
        if let spaceId, (task.fieldValues?.isEmpty == false || task.newFields?.isEmpty == false) {
            let resolved = try await FieldResolver.resolveAiCustomFields(
                db, spaceId: spaceId, customFields: customFields,
                newFields: task.newFields ?? [], fieldValues: task.fieldValues ?? []
            )
            customFieldValues = resolved.customFieldValues
        }

        return ResolvedTask(task: task, repoIds: repoIds, milestoneId: milestoneId, customFieldValues: customFieldValues)
    }

    /// Single "paste a task" flow, with optional space context (repos,
    /// milestones, custom fields, reference images) and an optional
    /// attached screenshot.
    public static func parseTask(_ db: ZenithDatabase, spaceId: UUID?, text: String, attachedImage: AttachedImage?) async throws -> ResolvedTask {
        var context = SpaceContext(spaceContext: nil, images: [], repos: [], milestones: [], customFields: [])
        if let spaceId {
            context = try await fetchSpaceContext(db, spaceId: spaceId, includeImages: true)
        }

        let task = try await Prompts.parseTaskFromText(
            text: text, spaceContext: context.spaceContext, spaceImages: context.images, attachedImage: attachedImage,
            repos: context.repos.map { Prompts.RepoContext(name: $0.name, context: $0.cachedContext) },
            milestones: context.milestones.map { Prompts.MilestoneContext(title: $0.title, description: $0.description) },
            customFields: context.customFields.map { Prompts.CustomFieldContext(key: $0.key, name: $0.name, type: $0.type.rawValue, options: optionLabels($0)) }
        )

        return try await resolveTask(db, spaceId: spaceId, task: task, repos: context.repos, milestones: context.milestones, customFields: context.customFields)
    }

    /// Bulk "paste a list" flow. Resolves fields **sequentially, not in
    /// parallel**, per task — mirrors the TS route exactly, so two tasks
    /// proposing the same new field in one paste don't race and
    /// double-create it.
    public static func parseTasks(_ db: ZenithDatabase, spaceId: UUID?, text: String) async throws -> [ResolvedTask] {
        var context = SpaceContext(spaceContext: nil, images: [], repos: [], milestones: [], customFields: [])
        if let spaceId {
            context = try await fetchSpaceContext(db, spaceId: spaceId, includeImages: false)
        }

        let tasks = try await Prompts.parseTasksFromText(
            text: text, spaceContext: context.spaceContext,
            repos: context.repos.map { Prompts.RepoContext(name: $0.name, context: $0.cachedContext) },
            milestones: context.milestones.map { Prompts.MilestoneContext(title: $0.title, description: $0.description) },
            customFields: context.customFields.map { Prompts.CustomFieldContext(key: $0.key, name: $0.name, type: $0.type.rawValue, options: optionLabels($0)) }
        )

        var fields = context.customFields
        var resolved: [ResolvedTask] = []
        for task in tasks {
            let result = try await resolveTask(db, spaceId: spaceId, task: task, repos: context.repos, milestones: context.milestones, customFields: fields)
            resolved.append(result)
            // Pick up any field the previous iteration just created, so the
            // next iteration's `findByKey` sees it too (same reasoning as
            // the sequential-not-parallel loop itself).
            if spaceId != nil {
                fields = try await CustomFieldQueries.getCustomFieldsForSpace(db, spaceId: spaceId!)
            }
        }
        return resolved
    }

    /// "Generate ✦" in the task detail drawer — no space context needed.
    public static func generateSubtasks(title: String, description: String?) async throws -> [String] {
        try await Prompts.generateSubtasks(title: title, description: description)
    }

    /// Manual "Sync" — the only way a repo's cached context is ever
    /// (re)generated. Never called from task-parsing; that only ever reads
    /// the cache.
    public static func syncRepoContext(_ db: ZenithDatabase, repoId: UUID, githubToken: String?) async throws -> Repo? {
        guard let repo = try await RepoQueries.getRepoById(db, id: repoId) else {
            throw ValidationError(field: "repo", message: "Repo not found.")
        }
        let snapshot = try await GitHubClient.getRepoSnapshot(repoUrl: repo.url, githubToken: githubToken)
        let summary = try await Prompts.summarizeRepoContext(snapshot)
        return try await RepoQueries.setCache(db, id: repoId, cachedContext: summary)
    }
}
