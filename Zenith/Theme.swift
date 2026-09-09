import SwiftUI
import ZenithData

/// Minimal shared semantic colors — everything else now comes straight
/// from system materials/colors (`.regularMaterial`, `Color.secondary`,
/// `.accentColor`, etc.) so the app tracks the user's actual system
/// appearance/accent-color preference automatically, instead of a
/// hand-rolled palette fighting the platform's own "glass" look.
enum Theme {
    static func priorityColor(_ priority: IssuePriority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    static func statusColor(_ status: IssueStatus) -> Color {
        switch status {
        case .backlog: return .secondary
        case .todo: return .blue
        case .inProgress: return .yellow
        case .done: return .green
        }
    }

    static func fieldColor(_ color: FieldColor)  -> Color {
        switch color {
        case .gray: return .gray
        case .blue: return .blue
        case .green: return .green
        case .purple: return .purple
        case .red: return .red
        case .yellow: return .yellow
        case .pink: return .pink
        case .orange: return .orange
        }
    }
}
