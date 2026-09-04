import SwiftUI
import ZenithData

/// Port of `roadmap-view.tsx`. Uses positioned SwiftUI views inside a
/// `ScrollView` rather than the audit's suggested `Canvas` — bars need to
/// be individually tappable (opens the task drawer, subtask 4 follow-up),
/// and `Canvas` content isn't hit-testable per-element, so plain views
/// with `.offset`/`.frame` give the same visual result with working tap
/// targets for less complexity.
struct RoadmapView: View {
    let model: SpaceDetailModel
    let view: ZView

    @State private var records: [IssueRecord] = []

    private let rowHeight: CGFloat = 36
    private let padDays = 4

    private var config: RoadmapViewConfig? {
        if case .roadmap(let config) = view.config { return config }
        return nil
    }

    private var registry: [FieldDef] {
        FieldRegistry.build(customFields: model.customFields, milestones: model.milestones, repos: model.repos)
    }

    private var hasDateOrIterationField: Bool {
        registry.contains { $0.isDateCapable }
    }

    private var startField: FieldDef? {
        config?.startFieldId.flatMap { FieldRegistry.fieldDef(in: registry, id: $0) }
    }

    private var endField: FieldDef? {
        config?.endFieldId.flatMap { FieldRegistry.fieldDef(in: registry, id: $0) }
    }

    private var dayWidth: CGFloat {
        switch config?.zoom ?? .month {
        case .week: return 32
        case .month: return 12
        case .quarter: return 5
        }
    }

    private struct RangedIssue: Identifiable {
        let issue: IssueRecord
        let start: String
        let end: String
        var id: UUID { issue.id }
    }

    private var ranged: [RangedIssue] {
        guard let startField, let endField else { return [] }
        let filtered = FilterEvaluation.apply(records, filters: config?.filters ?? [], registry: registry)
        return filtered.compactMap { issue in
            guard let range = RoadmapResolution.resolveRange(startField: startField, endField: endField, issue: issue) else { return nil }
            return RangedIssue(issue: issue, start: range.start, end: range.end)
        }
    }

    private var timelineRange: (start: String, end: String) {
        guard !ranged.isEmpty else {
            let today = ISODate.today()
            return (ISODate.addDays(today, -padDays), ISODate.addDays(today, 30))
        }
        var minStart = ranged[0].start
        var maxEnd = ranged[0].end
        for r in ranged {
            if r.start < minStart { minStart = r.start }
            if r.end > maxEnd { maxEnd = r.end }
        }
        return (ISODate.addDays(minStart, -padDays), ISODate.addDays(maxEnd, padDays))
    }

    private struct MonthBucket: Identifiable {
        let label: String
        let days: Int
        var id: String { label + String(days) }
    }

    private var months: [MonthBucket] {
        let (start, end) = timelineRange
        let totalDays = ISODate.daysBetween(start, end)
        guard totalDays > 0 else { return [] }

        var buckets: [MonthBucket] = []
        var cursor = start
        var remaining = totalDays
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        var monthGuard = 0
        while remaining > 0, monthGuard < 60 {
            monthGuard += 1
            let date = ISODate.parse(cursor)
            let label = formatter.string(from: date)
            let calendar = Calendar.current
            let range = calendar.range(of: .day, in: .month, for: date) ?? (1..<29)
            let dayOfMonth = calendar.component(.day, from: date)
            let daysLeftInMonth = range.count - dayOfMonth + 1
            let daysHere = min(daysLeftInMonth, remaining)
            buckets.append(MonthBucket(label: label, days: daysHere))
            cursor = ISODate.addDays(cursor, daysHere)
            remaining -= daysHere
        }
        return buckets
    }

    var body: some View {
        Group {
            if !hasDateOrIterationField {
                emptyState(
                    title: "Welcome to Roadmap!",
                    message: "This space needs at least one date or iteration field to get started."
                )
            } else if startField == nil || endField == nil {
                emptyState(
                    title: "Pick date fields for this view",
                    message: "Choose a start and end field (date or iteration) in view settings to start plotting tasks."
                )
            } else if ranged.isEmpty {
                emptyState(title: "Nothing to plot yet", message: "No tasks have both a start and end date set.")
            } else {
                timeline
            }
        }
        // Without this, the view sizes itself to fit its content instead
        // of filling the `NavigationSplitView` detail pane — the symptom
        // was the roadmap rendering small and centered instead of filling
        // the window.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: model.issues.map(\.id)) {
            records = await model.issueRecords()
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "calendar")
        } description: {
            Text(message)
        }
    }

    private var timeline: some View {
        let (rangeStart, _) = timelineRange
        let timelineWidth = CGFloat(ISODate.daysBetween(timelineRange.start, timelineRange.end)) * dayWidth
        let todayOffset = CGFloat(ISODate.daysBetween(rangeStart, ISODate.today())) * dayWidth

        return HStack(spacing: 0) {
            // Left column: issue titles, one row per ranged issue.
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: rowHeight * 2)
                ForEach(ranged) { entry in
                    HStack(spacing: 6) {
                        Circle().fill(Theme.priorityColor(entry.issue.priority)).frame(width: 6, height: 6)
                        Text(entry.issue.title).font(.callout).lineLimit(1)
                    }
                    .frame(height: rowHeight, alignment: .leading)
                    .padding(.horizontal, 10)
                }
            }
            .frame(width: 220, alignment: .leading)
            .overlay(alignment: .trailing) { Divider() }

            // Right side: scrollable month header + day-positioned bars.
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(months) { month in
                                Text(month.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: CGFloat(month.days) * dayWidth, height: rowHeight, alignment: .leading)
                                    .padding(.leading, 4)
                                    .overlay(alignment: .trailing) { Divider() }
                            }
                        }
                        .background(.regularMaterial)

                        Color.clear.frame(height: rowHeight)

                        ForEach(ranged) { _ in
                            Divider()
                                .frame(maxWidth: .infinity)
                                .frame(height: rowHeight, alignment: .bottom)
                        }
                    }

                    if todayOffset >= 0, todayOffset <= timelineWidth {
                        Rectangle().fill(.red.opacity(0.5)).frame(width: 1)
                            .offset(x: todayOffset)
                    }

                    ForEach(Array(ranged.enumerated()), id: \.element.id) { index, entry in
                        let left = CGFloat(ISODate.daysBetween(rangeStart, entry.start)) * dayWidth
                        let width = max(dayWidth, CGFloat(ISODate.daysBetween(entry.start, entry.end)) * dayWidth)
                        Text(entry.issue.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .frame(width: width, height: 20, alignment: .leading)
                            .background(Color.accentColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                            .offset(x: left, y: rowHeight * 2 + CGFloat(index) * rowHeight + (rowHeight - 20) / 2)
                    }
                }
                .frame(width: timelineWidth, alignment: .topLeading)
            }
        }
        .background(.background)
    }
}
