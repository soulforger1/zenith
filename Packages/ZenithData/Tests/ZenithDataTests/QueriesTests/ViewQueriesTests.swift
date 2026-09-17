import Foundation
import Testing

@testable import ZenithData

@Suite("ViewQueries")
struct ViewQueriesTests {
    @Test("getOrCreateDefaultViewsForSpace seeds Table/Board/Roadmap + starter fields, idempotently, with Board default")
    func seedsDefaultsIdempotently() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await SpaceQueries.createSpace(db, name: "Space", description: nil)

        let firstCall = try await ViewQueries.getOrCreateDefaultViewsForSpace(db, spaceId: space.id)
        #expect(firstCall.count == 3)
        #expect(Set(firstCall.map(\.name)) == ["Table", "Board", "Roadmap"])
        #expect(firstCall.first(where: { $0.name == "Board" })?.isDefault == true)

        let fields = try await CustomFieldQueries.getCustomFieldsForSpace(db, spaceId: space.id)
        #expect(Set(fields.map(\.key)) == ["assignees", "size"])

        let secondCall = try await ViewQueries.getOrCreateDefaultViewsForSpace(db, spaceId: space.id)
        #expect(secondCall.count == 3)
        #expect(Set(secondCall.map(\.id)) == Set(firstCall.map(\.id)))
    }

    @Test("setDefault unsets every other view's default flag in the same space")
    func setDefaultIsExclusive() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await SpaceQueries.createSpace(db, name: "Space", description: nil)
        let views = try await ViewQueries.getOrCreateDefaultViewsForSpace(db, spaceId: space.id)
        let table = views.first(where: { $0.name == "Table" })!

        _ = try await ViewQueries.setDefault(db, id: table.id)

        let after = try await ViewQueries.getViewsForSpace(db, spaceId: space.id)
        #expect(after.filter(\.isDefault).map(\.id) == [table.id])
    }

    @Test("deleteView refuses to delete a space's last remaining view")
    func deleteViewRefusesLast() async throws {
        let db = try ZenithDatabase.inMemory()
        let space = try await SpaceQueries.createSpace(db, name: "Space", description: nil)
        let view = try await ViewActions.createView(db, spaceId: space.id, name: "Only", type: .table)

        let error = try await ViewQueries.deleteView(db, id: view.id)
        #expect(error != nil)
        #expect(try await ViewQueries.getViewById(db, id: view.id) != nil)
    }
}
