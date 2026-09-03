/// Fixed palette for custom-field select options — port of
/// `lib/fields/colors.ts`. Semantic color names only; SwiftUI `Color`
/// mapping happens in the app target's `Theme.swift` (subtask 4).
public enum FieldColor: String, Codable, CaseIterable, Sendable {
    case gray, blue, green, purple, red, yellow, pink, orange
}

public enum FieldColors {
    public static let values: [FieldColor] = FieldColor.allCases

    public static func color(named name: String?) -> FieldColor {
        guard let name, let color = FieldColor(rawValue: name) else { return .gray }
        return color
    }
}
