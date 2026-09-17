import Foundation
import Testing

@testable import ZenithData

@Suite("SpaceQueries")
struct SpaceQueriesTests {
    @Test("createSpace slugifies the name and de-duplicates on collision")
    func createSpaceSlugCollision() async throws {
        let db = try ZenithDatabase.inMemory()
        let first = try await SpaceQueries.createSpace(db, name: "Work Stuff", description: nil)
        #expect(first.slug == "work-stuff")

        let second = try await SpaceQueries.createSpace(db, name: "Work Stuff", description: nil)
        #expect(second.slug == "work-stuff-2")
    }

    @Test("updateContext can explicitly clear the column")
    func updateContextClears() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await SpaceQueries.createSpace(db, name: "Space", description: nil)
        _ = try await SpaceQueries.updateContext(db, id: space.id, context: "some context")
        let cleared = try await SpaceQueries.updateContext(db, id: space.id, context: nil)
        #expect(cleared?.context == nil)
    }

    @Test("updateNameAndDescription leaves description untouched when nil is passed")
    func updateNameLeavesDescriptionUntouched() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await SpaceQueries.createSpace(db, name: "Space", description: "original")
        let updated = try await SpaceQueries.updateNameAndDescription(db, id: space.id, name: "Renamed", description: nil)
        #expect(updated?.name == "Renamed")
        #expect(updated?.description == "original")
    }

    @Test("deleting a space cascades to its issues and leaves tombstones")
    func deleteSpaceCascades() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await SpaceQueries.createSpace(db, name: "Space", description: nil)
        let issue = try await IssueQueries.createIssue(db, .init(spaceId: space.id, title: "Task"))

        try await SpaceQueries.deleteSpace(db, id: space.id)

        #expect(try await SpaceQueries.getSpaceById(db, id: space.id) == nil)
        #expect(try await IssueQueries.getIssueById(db, id: issue.id) == nil)

        let tombstoneCount = try await db.read { d in
            try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM sync_tombstones WHERE table_name = 'spaces' AND row_id = ?", arguments: [space.id.databaseText])
        }
        #expect(tombstoneCount == 1)
    }
}
