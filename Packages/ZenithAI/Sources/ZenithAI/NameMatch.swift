import Foundation

/// Port of `lib/name-match.ts`. Resolves a *name* Claude returned (a repo
/// name or a milestone title) back to a real id — matched case-
/// insensitively against the space's actual repos/milestones, so a
/// hallucinated or slightly-off name never gets attached to an issue.
public enum NameMatch {
    public static func resolveId(_ name: String?, items: [(id: UUID, name: String)]) -> UUID? {
        guard let name, !name.isEmpty else { return nil }
        return items.first { $0.name.lowercased() == name.lowercased() }?.id
    }

    /// Plural form for multi-value fields (repos) — resolves each name the
    /// same way as `resolveId`, drops any that don't match, and dedupes
    /// while preserving first-seen order (mirrors `[...new Set(ids)]`).
    public static func resolveIds(_ names: [String]?, items: [(id: UUID, name: String)]) -> [UUID] {
        guard let names, !names.isEmpty else { return [] }
        var seen = Set<UUID>()
        var result: [UUID] = []
        for name in names {
            guard let id = resolveId(name, items: items), !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(id)
        }
        return result
    }
}
