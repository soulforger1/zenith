import Foundation
import Testing

@testable import ZenithData

@Suite("IssueQueries")
struct IssueQueriesTests {
    private func makeSpace(_ db: ZenithDatabase) async throws -> Space {
        try await SpaceQueries.createSpace(db, name: "Space", description: nil)
    }

    @Test("createIssue then getIssueById round-trips every field")
    func createAndFetch() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await makeSpace(db)
        let created = try await IssueQueries.createIssue(
            db,
            .init(
                spaceId: space.id, title: "Ship it", description: "desc", status: .todo, priority: .high,
                tags: ["a", "b"], branch: "main", estimate: "2h", dueDate: "2026-01-15", startDate: "2026-01-01",
                customFieldValues: ["f1": .string("v1")]
            )
        )
        let fetched = try await IssueQueries.getIssueById(db, id: created.id)
        #expect(fetched?.title == "Ship it")
        #expect(fetched?.tags == ["a", "b"])
        #expect(fetched?.dueDate == "2026-01-15")
        #expect(fetched?.startDate == "2026-01-01")
        #expect(fetched?.customFieldValues["f1"] == .string("v1"))
        #expect(fetched?.status == .todo)
        #expect(fetched?.isClosed == false)
    }

    @Test("updateIssueFields: description??=nil clears, description not present leaves unchanged")
    func nullableClearSemantics() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await makeSpace(db)
        let issue = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "T", description: "original"))

        // Not part of the patch -> unchanged.
        let untouched = try await IssueQueries.updateIssueFields(db, id: issue.id, patch: .init(title: "Renamed"))
        #expect(untouched?.description == "original")

        // .some(nil) -> explicit clear.
        let cleared = try await IssueQueries.updateIssueFields(db, id: issue.id, patch: .init(description: .some(nil)))
        #expect(cleared?.description == nil)
    }

    @Test("updateIssueFields status=.done syncs isClosed and closedAt, reopening clears closedAt")
    func statusSyncsClosedState() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await makeSpace(db)
        let issue = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "T"))

        let closed = try await IssueQueries.updateIssueFields(db, id: issue.id, patch: .init(status: .done))
        #expect(closed?.isClosed == true)
        #expect(closed?.closedAt != nil)

        let reopened = try await IssueQueries.updateIssueFields(db, id: issue.id, patch: .init(status: .todo))
        #expect(reopened?.isClosed == false)
        #expect(reopened?.closedAt == nil)
    }

    @Test("updateIssueFields merges customFieldValues shallowly rather than overwriting")
    func customFieldValuesMerge() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await makeSpace(db)
        let issue = try await IssueQueries.createIssue(
            db, .init(spaceId: space.id, title: "T", customFieldValues: ["a": .string("1"), "b": .string("2")])
        )

        let updated = try await IssueQueries.updateIssueFields(db, id: issue.id, patch: .init(customFieldValues: ["b": .string("changed"), "c": .string("3")]))
        #expect(updated?.customFieldValues["a"] == .string("1"))
        #expect(updated?.customFieldValues["b"] == .string("changed"))
        #expect(updated?.customFieldValues["c"] == .string("3"))
    }

    @Test("updateIssueFields replaces repo links and bumps updated_at even for a repo-only patch")
    func repoOnlyPatchBumpsUpdatedAt() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await makeSpace(db)
        let repoA = try await RepoQueries.createRepo(db, spaceId: space.id, name: "a", url: "org/a")
        let repoB = try await RepoQueries.createRepo(db, spaceId: space.id, name: "b", url: "org/b")
        let issue = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "T", repoIds: [repoA.id]))
        let before = issue.updatedAt

        let updated = try await IssueQueries.updateIssueFields(db, id: issue.id, patch: .init(repoIds: [repoB.id]))
        #expect(updated!.updatedAt >= before)

        let links = try await IssueQueries.repoIds(db, forIssueIds: [issue.id])
        #expect(links[issue.id] == [repoB.id])
    }

    @Test("wouldCreateCycle detects a self-parent and an indirect ancestor loop")
    func cycleDetection() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await makeSpace(db)
        let a = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "A"))
        let b = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "B", parentId: a.id))

        #expect(try await IssueQueries.wouldCreateCycle(db, taskId: a.id, candidateParentId: b.id) == true)
        #expect(try await IssueQueries.wouldCreateCycle(db, taskId: a.id, candidateParentId: a.id) == true)

        let c = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "C"))
        #expect(try await IssueQueries.wouldCreateCycle(db, taskId: c.id, candidateParentId: b.id) == false)
    }

    @Test("deleting a milestone sets issues.milestoneId to nil instead of deleting them")
    func deleteMilestoneSetsNull() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await makeSpace(db)
        let milestone = try await MilestoneQueries.createMilestone(db, spaceId: space.id, title: "M1", description: nil, dueDate: nil)
        let issue = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "T", milestoneId: milestone.id))

        try await MilestoneQueries.deleteMilestone(db, id: milestone.id)

        let fetched = try await IssueQueries.getIssueById(db, id: issue.id)
        #expect(fetched != nil)
        #expect(fetched?.milestoneId == nil)
    }

    @Test("deleting a parent issue promotes children to standalone tasks")
    func deleteParentPromotesChildren() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await makeSpace(db)
        let parent = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "Parent"))
        let child = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "Child", parentId: parent.id))

        try await IssueQueries.deleteIssue(db, id: parent.id)

        let fetched = try await IssueQueries.getIssueById(db, id: child.id)
        #expect(fetched != nil)
        #expect(fetched?.parentId == nil)
    }

    @Test("issueCountsBySpace and upcomingIssues aggregate correctly")
    func aggregates() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await makeSpace(db)
        _ = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "Done", status: .done))
        let dueSoon = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "Due soon", dueDate: ISODate.addDays(ISODate.today(), 1)))
        _ = dueSoon

        let counts = try await IssueQueries.issueCountsBySpace(db)
        #expect(counts[space.id]?.total == 2)
        #expect(counts[space.id]?.open == 1)

        let upcoming = try await IssueQueries.upcomingIssues(db, daysAhead: 7)
        #expect(upcoming.contains { $0.title == "Due soon" })
        #expect(!upcoming.contains { $0.title == "Done" })
    }

    @Test("bulk operations update every id and skip on an empty list")
    func bulkOperations() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await makeSpace(db)
        let a = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "A"))
        let b = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "B"))

        try await IssueQueries.bulkUpdateStatus(db, ids: [a.id, b.id], status: .done)
        let afterStatus = try await IssueQueries.getIssuesForSpace(db, spaceId: space.id)
        #expect(afterStatus.allSatisfy { $0.isClosed })

        try await IssueQueries.bulkUpdatePriority(db, ids: [a.id], priority: .high)
        #expect(try await IssueQueries.getIssueById(db, id: a.id)?.priority == .high)
        #expect(try await IssueQueries.getIssueById(db, id: b.id)?.priority == .medium)

        try await IssueQueries.bulkDeleteIssues(db, ids: [a.id, b.id])
        #expect(try await IssueQueries.getIssuesForSpace(db, spaceId: space.id).isEmpty)

        // Empty-list guards shouldn't throw.
        try await IssueQueries.bulkUpdateStatus(db, ids: [], status: .done)
        try await IssueQueries.bulkDeleteIssues(db, ids: [])
    }
}
