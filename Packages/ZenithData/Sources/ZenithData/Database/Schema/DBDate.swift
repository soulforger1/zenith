import Foundation

/// GRDB's canonical `Date` ⇄ TEXT representation
/// (`"yyyy-MM-dd HH:mm:ss.SSS"`, UTC) — fixed-width, so lexical comparison
/// equals chronological comparison, which the sync layer relies on for
/// `WHERE updated_at > ?` delta queries. `ZenithDatabase`'s query layer
/// mostly never needs this directly (binding/reading a Swift `Date`
/// through GRDB does the same conversion internally), but the sync layer
/// builds/reads raw column text explicitly (`LocalSyncStore`, and
/// `ZenithSync`'s Postgres row mapping), so this is `public` — the one
/// place both sides must agree on the exact format.
public enum DBDate {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    public static func string(_ date: Date) -> String {
        formatter.string(from: date)
    }

    public static func parse(_ text: String) -> Date? {
        formatter.date(from: text)
    }
}
