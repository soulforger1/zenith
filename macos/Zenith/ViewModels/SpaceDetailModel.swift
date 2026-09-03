import Foundation
import Observation
import ZenithAI
import ZenithData

/// Backs the per-space shell (header/tabs) and whichever view is currently
/// selected — mirrors what `app/(app)/spaces/[spaceSlug]/layout.tsx` +
/// `views/[viewId]/page.tsx` fetch server-side (views, issues, milestones,
/// repos, custom fields), pulled once here and shared across the per-space
/// screens instead of a fresh RSC fetch per navigation.
@Observable
@MainActor
final class SpaceDetailModel {
    private(set) var space: Space
    private let database: ZenithDatabase

    private(set) var views: [ZView] = []
    private(set) var issues: [Issue] = []
    private(set) var milestones: [Milestone] = []
    private(set) var repos: [Repo] = []
    private(set) var customFields: [CustomField] = []
    private(set) var images: [SpaceImage] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    init(space: Space, database: ZenithDatabase) {
        self.space = space
        self.database = database
    }

    /// The view a bare space link lands on: the one marked `isDefault`, or
    /// the first view if none is (shouldn't happen once `load()` has run,
    /// which seeds the standard trio for a brand-new space).
    var defaultView: ZView? {
        views.first(where: \.isDefault) ?? views.first
    }

    func load() async {
        isLoading = true
        loadError = nil
        do {
            // Seeds Table/Board/Roadmap + starter custom fields the first
            // time this space is ever opened — idempotent, matches
            // `getOrCreateDefaultViewsForSpace`'s role on the web side.
            async let viewsTask = ViewQueries.getOrCreateDefaultViewsForSpace(
                database, spaceId: space.id)
            async let issuesTask = IssueQueries.getIssuesForSpace(database, spaceId: space.id)
            async let milestonesTask = MilestoneQueries.getMilestonesForSpace(
                database, spaceId: space.id)
            async let reposTask = RepoQueries.getReposForSpace(database, spaceId: space.id)
            async let customFieldsTask = CustomFieldQueries.getCustomFieldsForSpace(
                database, spaceId: space.id)
            async let imagesTask = SpaceImageQueries.getSpaceImages(database, spaceId: space.id)

            let (
                loadedViews, loadedIssues, loadedMilestones, loadedRepos, loadedFields, loadedImages
            ) =
                try await (
                    viewsTask, issuesTask, milestonesTask, reposTask, customFieldsTask, imagesTask
                )

            views = loadedViews.sorted { $0.position < $1.position }
            issues = loadedIssues
            milestones = loadedMilestones
            repos = loadedRepos
            customFields = loadedFields
            images = loadedImages
        } catch {
            loadError = error.diagnosticDescription
        }
        isLoading = false
    }

    func issueRecords() async -> [IssueRecord] {
        let ids = issues.map(\.id)
        guard !ids.isEmpty else { return [] }
        async let repoIdsTask = IssueQueries.repoIds(database, forIssueIds: ids)
        async let subtaskCountsTask = IssueQueries.subtaskCounts(database, forParentIds: ids)
        guard
            let (repoIdsByIssue, subtaskCountByIssue) = try? await (repoIdsTask, subtaskCountsTask)
        else {
            return issues.toRecords()
        }
        return issues.toRecords(
            repoIdsByIssue: repoIdsByIssue, subtaskCountByIssue: subtaskCountByIssue)
    }

    func updateIssueStatus(_ issueId: UUID, status: IssueStatus) async {
        do {
            _ = try await IssueActions.updateIssueFields(
                database, id: issueId, patch: .init(status: status))
            if let index = issues.firstIndex(where: { $0.id == issueId }) {
                issues[index].status = status
                issues[index].isClosed = status == .done
            }
        } catch {
            loadError = error.diagnosticDescription
        }
    }

    func updateIssuePriority(_ issueId: UUID, priority: IssuePriority) async {
        do {
            _ = try await IssueActions.updateIssueFields(
                database, id: issueId, patch: .init(priority: priority))
            if let index = issues.firstIndex(where: { $0.id == issueId }) {
                issues[index].priority = priority
            }
        } catch {
            loadError = error.diagnosticDescription
        }
    }

    /// Generic patch entry point for callers (the Board view's drag-drop)
    /// that need to set more than one field at once — mirrors
    /// `updateIssueGroupAction`. Keeps `issues` in sync locally the same
    /// way the single-field update methods above do.
    func applyPatch(_ issueId: UUID, patch: IssueFieldPatch) async {
        do {
            guard
                let updated = try await IssueActions.updateIssueFields(
                    database, id: issueId, patch: patch)
            else { return }
            if let index = issues.firstIndex(where: { $0.id == issueId }) {
                issues[index] = updated
            }
        } catch {
            loadError = error.diagnosticDescription
        }
    }

    func createQuickIssue(title: String, status: IssueStatus) async {
        do {
            try await IssueActions.createIssue(
                database, spaceId: space.id, status: status, title: title)
            await load()
        } catch {
            loadError = error.diagnosticDescription
        }
    }

    // MARK: - Task detail

    func issueRecord(_ id: UUID) async -> IssueRecord? {
        try? await IssueActions.getIssueRecord(database, id: id)
    }

    func childIssues(_ parentId: UUID) async -> [IssueRecord] {
        (try? await IssueActions.getChildIssues(database, parentId: parentId)) ?? []
    }

    func createSubtask(parentId: UUID, title: String) async -> IssueRecord? {
        try? await IssueActions.createSubtask(database, parentId: parentId, title: title)
    }

    func createSubtasksFromTitles(parentId: UUID, titles: [String]) async -> [IssueRecord] {
        (try? await IssueActions.createSubtasksFromTitles(database, parentId: parentId, titles: titles)) ?? []
    }

    /// `nil` unlinks (promotes the child back to a standalone task).
    func setParent(_ id: UUID, parentId: UUID?) async -> String? {
        do {
            try await IssueActions.setParent(database, id: id, parentId: parentId)
            return nil
        } catch {
            return error.diagnosticDescription
        }
    }

    func searchIssuesForSubtask(taskId: UUID, query: String) async -> [(id: UUID, title: String)] {
        (try? await IssueActions.searchIssuesForSubtask(database, taskId: taskId, query: query)) ?? []
    }

    func deleteIssue(_ id: UUID) async {
        do {
            try await IssueActions.deleteIssue(database, id: id)
            issues.removeAll { $0.id == id }
        } catch {
            loadError = error.diagnosticDescription
        }
    }

    /// "Generate ✦" in the task detail drawer — no space context needed, so
    /// this just forwards straight to `AIOrchestration`.
    func generateSubtasks(title: String, description: String?) async throws -> [String] {
        try await AIOrchestration.generateSubtasks(title: title, description: description)
    }

    // MARK: - AI paste-task modal

    func parseTask(text: String, attachedImage: AttachedImage?) async throws -> AIOrchestration.ResolvedTask {
        try await AIOrchestration.parseTask(database, spaceId: space.id, text: text, attachedImage: attachedImage)
    }

    func parseTasks(text: String) async throws -> [AIOrchestration.ResolvedTask] {
        try await AIOrchestration.parseTasks(database, spaceId: space.id, text: text)
    }

    /// Commit path for the AI paste-task modal's single-task mode.
    func createIssueFromDraft(_ draft: IssueActions.TaskDraft) async -> String? {
        do {
            try await IssueActions.createIssueFromDraft(database, spaceId: space.id, draft: draft)
            await load()
            return nil
        } catch {
            return error.diagnosticDescription
        }
    }

    /// Commit path for the AI paste-task modal's list mode.
    func createIssuesFromDrafts(_ drafts: [IssueActions.TaskDraft]) async -> String? {
        do {
            try await IssueActions.createIssuesFromDrafts(database, spaceId: space.id, drafts: drafts)
            await load()
            return nil
        } catch {
            return error.diagnosticDescription
        }
    }

    // MARK: - Milestones

    func createMilestone(title: String, description: String?, dueDate: String?) async throws {
        _ = try await MilestoneActions.createMilestone(
            database, spaceId: space.id,
            .init(title: title, description: description, dueDate: dueDate)
        )
        await load()
    }

    func updateMilestone(_ id: UUID, title: String, description: String?, dueDate: String?)
        async throws
    {
        _ = try await MilestoneActions.updateMilestone(
            database, id: id, .init(title: title, description: description, dueDate: dueDate))
        await load()
    }

    func toggleMilestoneClosed(_ id: UUID, isClosed: Bool) async {
        do {
            if let updated = try await MilestoneActions.toggleClosed(
                database, id: id, isClosed: isClosed),
                let index = milestones.firstIndex(where: { $0.id == id })
            {
                milestones[index] = updated
            }
        } catch {
            loadError = error.diagnosticDescription
        }
    }

    func deleteMilestone(_ id: UUID) async {
        do {
            try await MilestoneActions.deleteMilestone(database, id: id)
            milestones.removeAll { $0.id == id }
        } catch {
            loadError = error.diagnosticDescription
        }
    }

    /// The AI paste-task modal's field resolver can silently create new
    /// custom fields (or grow a select field's options) mid-parse — called
    /// right after a parse completes so the modal's draft-editing UI shows
    /// them without needing a full `load()`.
    func refreshCustomFields() async {
        if let fields = try? await CustomFieldQueries.getCustomFieldsForSpace(database, spaceId: space.id) {
            customFields = fields
        }
    }

    // MARK: - Settings: space context

    func updateContext(_ context: String) async {
        do {
            if let updated = try await SpaceActions.updateContext(
                database, id: space.id, context: context)
            {
                space = updated
            }
        } catch {
            loadError = error.diagnosticDescription
        }
    }

    // MARK: - Settings: custom fields

    func createCustomField(name: String, type: CustomFieldType, options: FieldOptions) async
        -> String?
    {
        do {
            let field = try await CustomFieldActions.createCustomField(
                database, spaceId: space.id, name: name, type: type, options: options)
            customFields.append(field)
            customFields.sort { $0.position < $1.position }
            return nil
        } catch {
            return error.diagnosticDescription
        }
    }

    func updateCustomField(_ id: UUID, name: String?, options: FieldOptions?) async -> String? {
        do {
            guard
                let updated = try await CustomFieldActions.updateCustomField(
                    database, id: id, name: name, options: options)
            else { return nil }
            if let index = customFields.firstIndex(where: { $0.id == id }) {
                customFields[index] = updated
            }
            return nil
        } catch {
            return error.diagnosticDescription
        }
    }

    func deleteCustomField(_ id: UUID) async {
        do {
            try await CustomFieldActions.deleteCustomField(database, id: id)
            customFields.removeAll { $0.id == id }
        } catch {
            loadError = error.diagnosticDescription
        }
    }

    // MARK: - Settings: GitHub repos

    func createRepo(name: String, url: String) async -> String? {
        do {
            let repo = try await RepoActions.createRepo(
                database, spaceId: space.id, .init(name: name, url: url))
            repos.append(repo)
            repos.sort { $0.name < $1.name }
            return nil
        } catch {
            return error.diagnosticDescription
        }
    }

    func deleteRepo(_ id: UUID) async {
        do {
            try await RepoActions.deleteRepo(database, id: id)
            repos.removeAll { $0.id == id }
        } catch {
            loadError = error.diagnosticDescription
        }
    }

    /// Manual "Sync" — the only way a repo's cached AI context is ever
    /// (re)generated. Runs a real network fetch + a real `claude` CLI
    /// call, so it's genuinely slow (seconds, not instant).
    func syncRepo(_ id: UUID) async -> String? {
        do {
            guard
                let updated = try await AIOrchestration.syncRepoContext(
                    database, repoId: id, githubToken: KeychainStore.githubToken())
            else {
                return nil
            }
            if let index = repos.firstIndex(where: { $0.id == id }) { repos[index] = updated }
            return nil
        } catch {
            return error.diagnosticDescription
        }
    }

    // MARK: - Settings: reference images

    func addImage(data: Data, mimeType: String, label: String?) async -> String? {
        do {
            let image = try await SpaceActions.addSpaceImage(
                database, spaceId: space.id, imageData: data, mimeType: mimeType, label: label)
            images.append(image)
            return nil
        } catch {
            return error.diagnosticDescription
        }
    }

    func deleteImage(_ id: UUID) async {
        do {
            try await SpaceActions.deleteSpaceImage(database, id: id)
            images.removeAll { $0.id == id }
        } catch {
            loadError = error.diagnosticDescription
        }
    }
}
