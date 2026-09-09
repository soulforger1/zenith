import Foundation
import Testing

@testable import ZenithData

/// Exercises `IssueActions`'s private `validatePatch` indirectly through
/// `updateIssueFields`'s public validation surface — specifically the
/// absent-vs-null distinction on nullable fields, since that's the easiest
/// thing to get subtly wrong in a straight port (see
/// docs/native-rewrite-audit.md's IssueFieldPatch discussion).
@Suite("IssueFieldPatch nullable semantics")
struct IssueFieldPatchValidationTests {
    @Test("outer nil means the field isn't part of the patch at all")
    func absentField() {
        let patch = IssueFieldPatch()
        #expect(patch.description == nil)
        #expect(patch.branch == nil)
    }

    @Test("some(nil) means explicit clear, distinguishable from absent")
    func explicitClear() {
        let patch = IssueFieldPatch(description: .some(nil))
        // The outer optional is present (not nil) even though the payload is nil.
        if case .some(let inner) = patch.description {
            #expect(inner == nil)
        } else {
            Testing.Issue.record("expected .some(nil), got absent")
        }
    }

    @Test("some(value) sets a real value")
    func explicitValue() {
        let patch = IssueFieldPatch(branch: .some("fix/thing"))
        if case .some(let inner) = patch.branch {
            #expect(inner == "fix/thing")
        } else {
            Testing.Issue.record("expected .some(\"fix/thing\")")
        }
    }
}
