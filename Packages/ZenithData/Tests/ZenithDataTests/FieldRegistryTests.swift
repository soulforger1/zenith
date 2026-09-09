import Foundation
import Testing

@testable import ZenithData

@Suite("FieldRegistry")
struct FieldRegistryTests {
    private func makeIssue(status: IssueStatus = .backlog, priority: IssuePriority = .medium, milestoneId: UUID? = nil) -> IssueRecord {
        IssueRecord(
            id: UUID(), title: "Test", description: nil, status: status, priority: priority, tags: [],
            branch: nil, estimate: nil, parentId: nil, subtaskCount: .zero, dueDate: nil, startDate: nil,
            milestoneId: milestoneId, repoIds: [], customFieldValues: [:], position: 0
        )
    }

    @Test("status field groups by the issue's status")
    func statusGroupKey() {
        let issue = makeIssue(status: .inProgress)
        #expect(FieldDef.status.groupKey(for: issue) == "in_progress")
    }

    @Test("status patch resolves an unknown key to backlog, matching the TS fallback")
    func statusPatchFallback() {
        let patch = FieldDef.status.patch(forGroupKey: nil)
        #expect(patch.status == .backlog)
    }

    @Test("milestone field groups by the issue's milestoneId")
    func milestoneGroupKey() {
        let milestoneId = UUID()
        let issue = makeIssue(milestoneId: milestoneId)
        #expect(FieldDef.milestone(options: []).groupKey(for: issue) == milestoneId.uuidString)
    }

    @Test("build() includes every custom field regardless of type, matching buildFieldRegistry's full scope")
    func buildIncludesAllFieldTypes() {
        let now = Date()
        let selectField = CustomField(
            id: UUID(), spaceId: UUID(), key: "size", name: "Size", type: .singleSelect,
            options: .fields([]), position: 0, createdAt: now, updatedAt: now
        )
        let textField = CustomField(
            id: UUID(), spaceId: UUID(), key: "notes", name: "Notes", type: .text,
            options: .fields([]), position: 1, createdAt: now, updatedAt: now
        )
        let registry = FieldRegistry.build(customFields: [selectField, textField], milestones: [])
        #expect(registry.contains { $0.id == selectField.id.uuidString })
        #expect(registry.contains { $0.id == textField.id.uuidString })
    }

    @Test("isGroupable is true only for single-value discrete fields")
    func isGroupableRestriction() {
        let now = Date()
        let selectField = CustomField(
            id: UUID(), spaceId: UUID(), key: "size", name: "Size", type: .singleSelect,
            options: .fields([]), position: 0, createdAt: now, updatedAt: now
        )
        #expect(FieldDef.status.isGroupable)
        #expect(FieldDef.custom(selectField).isGroupable)
        #expect(!FieldDef.dueDate.isGroupable)
        #expect(!FieldDef.startDate.isGroupable)
    }

    @Test("isDateCapable is true only for date/iteration fields")
    func isDateCapableRestriction() {
        #expect(FieldDef.dueDate.isDateCapable)
        #expect(FieldDef.startDate.isDateCapable)
        #expect(!FieldDef.status.isDateCapable)
        #expect(!FieldDef.priority.isDateCapable)
    }

    @Test("resolveRange for dueDate/startDate uses whichever is set, ordering start before end")
    func resolveRangeBuiltInDates() {
        var issue = makeIssue()
        issue.startDate = "2026-03-10"
        issue.dueDate = "2026-03-05"
        // start > end as given — resolveRange should swap them
        let range = RoadmapResolution.resolveRange(startField: .startDate, endField: .dueDate, issue: issue)
        #expect(range?.start == "2026-03-05")
        #expect(range?.end == "2026-03-10")
    }

    @Test("resolveRange returns nil when neither date is set")
    func resolveRangeNilWhenNoDates() {
        let issue = makeIssue()
        #expect(RoadmapResolution.resolveRange(startField: .startDate, endField: .dueDate, issue: issue) == nil)
    }

    @Test("resolveRange for a same-field iteration derives the end from start+duration")
    func resolveRangeIteration() {
        let now = Date()
        let iterationField = CustomField(
            id: UUID(), spaceId: UUID(), key: "sprint", name: "Sprint", type: .iteration,
            options: .iterations([IterationOption(id: "iter-1", title: "Sprint 1", startDate: "2026-01-01", durationDays: 14)]),
            position: 0, createdAt: now, updatedAt: now
        )
        var issue = makeIssue()
        issue.customFieldValues[iterationField.id.uuidString] = .string("iter-1")
        let field = FieldDef.custom(iterationField)
        let range = RoadmapResolution.resolveRange(startField: field, endField: field, issue: issue)
        #expect(range?.start == "2026-01-01")
        #expect(range?.end == "2026-01-15")
    }

    // MARK: - Table-only built-ins (tags/repoIds/branch/estimate), added
    // during subtask 7's parity pass — `buildFieldRegistry` on the web
    // side always included these 4 alongside status/priority/milestone/
    // dueDate/startDate; the earlier Board/Roadmap-driven port had
    // silently dropped them since neither of those views needed them.

    @Test("build() includes tags/repoIds/branch/estimate alongside the original 5 built-ins")
    func buildIncludesAllNineBuiltIns() {
        let registry = FieldRegistry.build(customFields: [], milestones: [])
        let ids = Set(registry.map(\.id))
        #expect(ids == ["status", "priority", "milestoneId", "dueDate", "startDate", "tags", "repoIds", "branch", "estimate"])
    }

    @Test("none of tags/repoIds/branch/estimate are groupable or date-capable")
    func newBuiltInsAreDisplayOnly() {
        for field in [FieldDef.tags, .repoIds(options: []), .branch, .estimate] {
            #expect(!field.isGroupable)
            #expect(!field.isDateCapable)
        }
    }

    @Test("displayValue is .empty for absent/empty values across every field kind")
    func displayValueEmpty() {
        let issue = makeIssue()
        #expect(FieldDef.dueDate.displayValue(for: issue) == .empty)
        #expect(FieldDef.tags.displayValue(for: issue) == .empty)
        #expect(FieldDef.branch.displayValue(for: issue) == .empty)
        #expect(FieldDef.estimate.displayValue(for: issue) == .empty)
        #expect(FieldDef.repoIds(options: []).displayValue(for: issue) == .empty)
    }

    @Test("displayValue renders tags as rawTags (no fixed option list)")
    func displayValueTags() {
        var issue = makeIssue()
        issue.tags = ["frontend", "bug"]
        #expect(FieldDef.tags.displayValue(for: issue) == .rawTags(["frontend", "bug"]))
    }

    @Test("displayValue renders branch with the branch case, not plain text")
    func displayValueBranch() {
        var issue = makeIssue()
        issue.branch = "feature/x"
        #expect(FieldDef.branch.displayValue(for: issue) == .branch("feature/x"))
    }

    @Test("displayValue resolves repoIds against the field's own repo options")
    func displayValueRepoIds() {
        let repoId = UUID()
        var issue = makeIssue()
        issue.repoIds = [repoId]
        let field = FieldDef.repoIds(options: [NormalizedOption(id: repoId.uuidString, label: "zenith", color: "gray")])
        #expect(field.displayValue(for: issue) == .options([NormalizedOption(id: repoId.uuidString, label: "zenith", color: "gray")]))
    }

    @Test("displayValue formats a whole-number custom field without a trailing .0")
    func displayValueWholeNumber() {
        let now = Date()
        let numberField = CustomField(
            id: UUID(), spaceId: UUID(), key: "points", name: "Points", type: .number,
            options: .fields([]), position: 0, createdAt: now, updatedAt: now
        )
        var issue = makeIssue()
        issue.customFieldValues[numberField.id.uuidString] = .number(5)
        #expect(FieldDef.custom(numberField).displayValue(for: issue) == .text("5"))
    }

    @Test("displayValue resolves a multi-select custom field's ids to their options")
    func displayValueMultiSelect() {
        let now = Date()
        let opt = FieldOption(id: "opt-1", name: "Backend", color: "blue")
        let multiField = CustomField(
            id: UUID(), spaceId: UUID(), key: "areas", name: "Areas", type: .multiSelect,
            options: .fields([opt]), position: 0, createdAt: now, updatedAt: now
        )
        var issue = makeIssue()
        issue.customFieldValues[multiField.id.uuidString] = .array([.string("opt-1")])
        #expect(FieldDef.custom(multiField).displayValue(for: issue) == .options([NormalizedOption(id: "opt-1", label: "Backend", color: "blue")]))
    }
}
