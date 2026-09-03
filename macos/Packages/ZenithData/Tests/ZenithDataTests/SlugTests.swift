import Testing

@testable import ZenithData

@Suite("Slug")
struct SlugTests {
    @Test("lowercases and hyphenates")
    func basic() {
        #expect(Slug.slugify("My Side Project") == "my-side-project")
    }

    @Test("strips leading/trailing separators")
    func trimsSeparators() {
        #expect(Slug.slugify("  --Weird Name!! ") == "weird-name")
    }

    @Test("collapses runs of non-alphanumeric characters")
    func collapsesRuns() {
        #expect(Slug.slugify("a---b___c") == "a-b-c")
    }

    @Test("truncates to 64 characters")
    func truncates() {
        let long = String(repeating: "a", count: 100)
        #expect(Slug.slugify(long).count == 64)
    }

    @Test("empty input produces an empty slug")
    func empty() {
        #expect(Slug.slugify("   ") == "")
    }
}
