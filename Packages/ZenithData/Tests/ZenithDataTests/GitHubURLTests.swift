import Testing

@testable import ZenithData

@Suite("GitHubURL")
struct GitHubURLTests {
    @Test("accepts a bare owner/repo")
    func bareForm() throws {
        let parsed = try GitHubURL.parse("zolboo/zenith")
        #expect(parsed.owner == "zolboo")
        #expect(parsed.repo == "zenith")
    }

    @Test("accepts a github.com/owner/repo form without scheme")
    func hostForm() throws {
        let parsed = try GitHubURL.parse("github.com/zolboo/zenith")
        #expect(parsed.owner == "zolboo")
        #expect(parsed.repo == "zenith")
    }

    @Test("accepts a full https URL with a .git suffix")
    func fullURLWithGitSuffix() throws {
        // Matches `parseRepoUrl`'s TS regex order exactly: `.git$` is
        // stripped before trailing slashes, so a `.git/` combination (with
        // a slash *after* `.git`) isn't stripped by either version — not
        // tested here since it isn't realistic input.
        let parsed = try GitHubURL.parse("https://github.com/zolboo/zenith.git")
        #expect(parsed.owner == "zolboo")
        #expect(parsed.repo == "zenith")
    }

    @Test("accepts a full https URL with a trailing slash")
    func fullURLWithTrailingSlash() throws {
        let parsed = try GitHubURL.parse("https://github.com/zolboo/zenith/")
        #expect(parsed.owner == "zolboo")
        #expect(parsed.repo == "zenith")
    }

    @Test("rejects a malformed input")
    func rejectsInvalid() {
        #expect(throws: (any Error).self) {
            try GitHubURL.parse("not a repo at all")
        }
    }

    @Test("rejects a bare owner with no repo segment")
    func rejectsMissingRepo() {
        #expect(throws: (any Error).self) {
            try GitHubURL.parse("zolboo")
        }
    }
}
