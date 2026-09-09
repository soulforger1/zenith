/// Port of `lib/priority.ts`'s label table (color-class lookups don't apply
/// natively — those become `Theme.swift` mappings in the app target).
public enum PriorityLabel {
    public static func label(for priority: IssuePriority) -> String {
        switch priority {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}
