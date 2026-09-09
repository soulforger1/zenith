import Foundation

/// Port of `lib/slug.ts`.
public enum Slug {
    public static func slugify(_ input: String) -> String {
        let lowered = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = lowered.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "-",
            options: .regularExpression
        )
        let trimmed = collapsed.replacingOccurrences(
            of: "^-+|-+$",
            with: "",
            options: .regularExpression
        )
        return String(trimmed.prefix(64))
    }
}
