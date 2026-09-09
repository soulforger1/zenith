import Foundation
import Observation
import ZenithData

/// Backs both `AppSidebar` (space list + counts) and `SpacesDashboardView`
/// (cards + "Upcoming" widget) — mirrors what `app/(app)/layout.tsx` +
/// `app/(app)/spaces/page.tsx` fetch server-side in the web app, just
/// pulled once here and shared instead of two separate server components.
@Observable
@MainActor
final class SpacesListModel {
    struct SpaceSummary: Identifiable, Sendable {
        let space: Space
        var openCount: Int
        var totalCount: Int
        var id: UUID { space.id }
    }

    private(set) var summaries: [SpaceSummary] = []
    private(set) var upcoming: [IssueQueries.UpcomingIssue] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    private let database: ZenithDatabase
    private let toasts: ToastCenter

    init(database: ZenithDatabase, toasts: ToastCenter) {
        self.database = database
        self.toasts = toasts
    }

    func load() async {
        isLoading = true
        loadError = nil
        do {
            async let spacesTask = SpaceQueries.getSpaces(database)
            async let countsTask = IssueQueries.issueCountsBySpace(database)
            async let upcomingTask = IssueQueries.upcomingIssues(database, daysAhead: 7)
            let (spaces, counts, upcomingIssues) = try await (spacesTask, countsTask, upcomingTask)

            summaries = spaces.map { space in
                let counts = counts[space.id] ?? .init(total: 0, open: 0)
                return SpaceSummary(space: space, openCount: counts.open, totalCount: counts.total)
            }
            upcoming = upcomingIssues
        } catch {
            loadError = error.diagnosticDescription
        }
        isLoading = false
    }

    func createSpace(name: String, description: String?) async throws -> Space {
        let space = try await SpaceActions.createSpace(database, .init(name: name, description: description))
        await load()
        toasts.success("Space created")
        return space
    }
}
