import Testing

@testable import ZenithData

@Suite("SpaceActions.SpaceInput validation")
struct SpaceActionsValidationTests {
    @Test("rejects an empty name")
    func rejectsEmptyName() {
        let input = SpaceActions.SpaceInput(name: "   ", description: nil)
        #expect(throws: ValidationError.self) {
            _ = try input.validate()
        }
    }

    @Test("rejects a name over 100 characters")
    func rejectsLongName() {
        let input = SpaceActions.SpaceInput(name: String(repeating: "a", count: 101), description: nil)
        #expect(throws: ValidationError.self) {
            _ = try input.validate()
        }
    }

    @Test("trims name and description")
    func trims() throws {
        let input = SpaceActions.SpaceInput(name: "  Side Projects  ", description: "  stuff  ")
        let (name, description) = try input.validate()
        #expect(name == "Side Projects")
        #expect(description == "stuff")
    }

    @Test("an all-whitespace description collapses to nil, same as the TS `|| undefined` guard")
    func blankDescriptionBecomesNil() throws {
        let input = SpaceActions.SpaceInput(name: "Work", description: "   ")
        let (_, description) = try input.validate()
        #expect(description == nil)
    }
}
