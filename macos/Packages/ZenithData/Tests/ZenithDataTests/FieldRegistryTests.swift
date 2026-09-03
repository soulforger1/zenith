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
}
