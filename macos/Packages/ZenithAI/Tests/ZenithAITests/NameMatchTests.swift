import Foundation
import Testing

@testable import ZenithAI

@Suite("NameMatch")
struct NameMatchTests {
    let repoA = UUID()
    let repoB = UUID()

    @Test("matches case-insensitively")
    func caseInsensitive() {
        let items = [(id: repoA, name: "Web"), (id: repoB, name: "API")]
        #expect(NameMatch.resolveId("web", items: items) == repoA)
        #expect(NameMatch.resolveId("API", items: items) == repoB)
    }

    @Test("returns nil for a name with no match, never guesses")
    func noMatch() {
        let items = [(id: repoA, name: "Web")]
        #expect(NameMatch.resolveId("Worker", items: items) == nil)
    }

    @Test("returns nil for a nil or empty name")
    func nilOrEmpty() {
        let items = [(id: repoA, name: "Web")]
        #expect(NameMatch.resolveId(nil, items: items) == nil)
        #expect(NameMatch.resolveId("", items: items) == nil)
    }

    @Test("resolveIds drops non-matches and dedupes, preserving first-seen order")
    func pluralForm() {
        let items = [(id: repoA, name: "Web"), (id: repoB, name: "API")]
        let ids = NameMatch.resolveIds(["Web", "Nonexistent", "api", "web"], items: items)
        #expect(ids == [repoA, repoB])
    }
}
