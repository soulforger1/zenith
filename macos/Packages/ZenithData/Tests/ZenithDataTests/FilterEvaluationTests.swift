import Foundation
import Testing

@testable import ZenithData

@Suite("FilterEvaluation")
struct FilterEvaluationTests {
    private let milestoneA = UUID()
    private let milestoneB = UUID()

    private func makeIssue(
        title: String = "Test",
        status: IssueStatus = .todo,
        priority: IssuePriority = .medium,
        tags: [String] = [],
        dueDate: String? = nil,
        milestoneId: UUID? = nil,
        customFieldValues: [String: AnyCodableValue] = [:]
    ) -> IssueRecord {
        IssueRecord(
            id: UUID(), title: title, description: nil, status: status, priority: priority, tags: tags,
            branch: nil, estimate: nil, parentId: nil, subtaskCount: .zero, dueDate: dueDate, startDate: nil,
            milestoneId: milestoneId, repoIds: [], customFieldValues: customFieldValues, position: 0
        )
    }

    private var registry: [FieldDef] {
        FieldRegistry.build(customFields: [], milestones: [
            Milestone(id: milestoneA, spaceId: UUID(), title: "M1", description: nil, dueDate: nil,
                status: "open", closedAt: nil, createdAt: Date(), updatedAt: Date()),
            Milestone(id: milestoneB, spaceId: UUID(), title: "M2", description: nil, dueDate: nil,
                status: "open", closedAt: nil, createdAt: Date(), updatedAt: Date()),
        ])
    }

    @Test("no rules is a pass-through")
    func emptyRules() {
        let issues = [makeIssue(), makeIssue()]
        #expect(FilterEvaluation.apply(issues, filters: [], registry: registry).count == 2)
    }

    @Test("`is` matches a built-in enum field")
    func isOperatorStatus() {
        let issues = [makeIssue(status: .todo), makeIssue(status: .done)]
        let rule = FilterRule(fieldId: "status", operatorType: .isEqual, value: .string("done"))
        let result = FilterEvaluation.apply(issues, filters: [rule], registry: registry)
        #expect(result.count == 1)
        #expect(result.first?.status == .done)
    }

    @Test("`is_not` excludes the matching value")
    func isNotOperator() {
        let issues = [makeIssue(priority: .high), makeIssue(priority: .low)]
        let rule = FilterRule(fieldId: "priority", operatorType: .isNot, value: .string("high"))
        #expect(FilterEvaluation.apply(issues, filters: [rule], registry: registry).first?.priority == .low)
    }

    @Test("`is_any_of` matches milestone membership")
    func isAnyOfMilestone() {
        let issues = [
            makeIssue(milestoneId: milestoneA),
            makeIssue(milestoneId: milestoneB),
            makeIssue(milestoneId: nil),
        ]
        let rule = FilterRule(
            fieldId: "milestoneId", operatorType: .isAnyOf,
            value: .array([.string(milestoneA.uuidString)]))
        let result = FilterEvaluation.apply(issues, filters: [rule], registry: registry)
        #expect(result.count == 1)
        #expect(result.first?.milestoneId == milestoneA)
    }

    @Test("`is_empty` / `is_not_empty` on milestone")
    func emptyOperators() {
        let issues = [makeIssue(milestoneId: milestoneA), makeIssue(milestoneId: nil)]
        let empty = FilterRule(fieldId: "milestoneId", operatorType: .isEmpty, value: nil)
        let notEmpty = FilterRule(fieldId: "milestoneId", operatorType: .isNotEmpty, value: nil)
        #expect(FilterEvaluation.apply(issues, filters: [empty], registry: registry).first?.milestoneId == nil)
        #expect(FilterEvaluation.apply(issues, filters: [notEmpty], registry: registry).first?.milestoneId == milestoneA)
    }

    @Test("`contains` is a case-insensitive substring test over tags")
    func containsOperatorTags() {
        let issues = [makeIssue(tags: ["Frontend"]), makeIssue(tags: ["backend"])]
        let rule = FilterRule(fieldId: "tags", operatorType: .contains, value: .string("front"))
        #expect(FilterEvaluation.apply(issues, filters: [rule], registry: registry).count == 1)
    }

    @Test("`before` / `after` bracket a due-date window (inclusive via ±1 day nudge)")
    func dateRangeWindow() {
        let issues = [
            makeIssue(dueDate: "2026-01-05"),
            makeIssue(dueDate: "2026-01-15"),
            makeIssue(dueDate: "2026-02-01"),
            makeIssue(dueDate: nil),
        ]
        // Window [2026-01-05, 2026-01-15] — stored bounds nudged one day out.
        let from = FilterRule(fieldId: "dueDate", operatorType: .after, value: .string("2026-01-04"))
        let to = FilterRule(fieldId: "dueDate", operatorType: .before, value: .string("2026-01-16"))
        let result = FilterEvaluation.apply(issues, filters: [from, to], registry: registry)
        #expect(Set(result.map(\.dueDate)) == ["2026-01-05", "2026-01-15"])
    }

    @Test("multiple rules AND together")
    func multipleRulesAreAnded() {
        let issues = [
            makeIssue(status: .todo, priority: .high),
            makeIssue(status: .todo, priority: .low),
            makeIssue(status: .done, priority: .high),
        ]
        let rules = [
            FilterRule(fieldId: "status", operatorType: .isEqual, value: .string("todo")),
            FilterRule(fieldId: "priority", operatorType: .isEqual, value: .string("high")),
        ]
        let result = FilterEvaluation.apply(issues, filters: rules, registry: registry)
        #expect(result.count == 1)
    }

    @Test("a rule for an unknown field id passes everything, matching the TS fallback")
    func unknownFieldPasses() {
        let issues = [makeIssue(), makeIssue()]
        let rule = FilterRule(fieldId: "since-deleted-custom-field", operatorType: .isEqual, value: .string("x"))
        #expect(FilterEvaluation.apply(issues, filters: [rule], registry: registry).count == 2)
    }

    @Test("`is` matches a custom single-select field value")
    func customSingleSelect() {
        let now = Date()
        let field = CustomField(
            id: UUID(), spaceId: UUID(), key: "size", name: "Size", type: .singleSelect,
            options: .fields([FieldOption(id: "lg", name: "Large", color: "blue")]),
            position: 0, createdAt: now, updatedAt: now
        )
        let reg = FieldRegistry.build(customFields: [field], milestones: [])
        let issues = [
            makeIssue(customFieldValues: [field.id.uuidString: .string("lg")]),
            makeIssue(customFieldValues: [:]),
        ]
        let rule = FilterRule(fieldId: field.id.uuidString, operatorType: .isEqual, value: .string("lg"))
        #expect(FilterEvaluation.apply(issues, filters: [rule], registry: reg).count == 1)
    }

    @Test("FilterRule round-trips its value through valueJSON")
    func valueRoundTrip() {
        let rule = FilterRule(fieldId: "status", operatorType: .isEqual, value: .string("done"))
        #expect(rule.value == .string("done"))
        let arrayRule = FilterRule(fieldId: "x", operatorType: .isAnyOf, value: .array([.string("a"), .string("b")]))
        #expect(arrayRule.value == .array([.string("a"), .string("b")]))
    }
}
