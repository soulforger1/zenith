/// Fractional-index helpers for drag-and-drop ordering — port of
/// `lib/position.ts`. Inserting between two existing items only ever
/// touches the moved row (never renumbers a whole column), at the cost of
/// position values that can theoretically converge over many repeated
/// inserts in the same spot — a non-issue at solo-user scale.
public enum Position {
    public static let gap: Double = 1000

    public static func atEnd(_ maxPosition: Double?) -> Double {
        guard let maxPosition else { return gap }
        return maxPosition + gap
    }

    public static func between(_ before: Double?, _ after: Double?) -> Double {
        switch (before, after) {
        case (nil, nil):
            return gap
        case (nil, .some(let after)):
            return after - gap / 2
        case (.some(let before), nil):
            return before + gap
        case (.some(let before), .some(let after)):
            return (before + after) / 2
        }
    }
}
