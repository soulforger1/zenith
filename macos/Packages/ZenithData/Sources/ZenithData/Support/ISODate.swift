import Foundation

/// Port of `lib/date.ts`'s ISO-date helpers. `YYYY-MM-DD` strings are
/// parsed as local-timezone midnight (not UTC) — same reasoning as the TS
/// `parseISODate` comment: `Date("2026-08-23")` in JS (and a naive
/// `ISO8601DateFormatter` in Swift) parses as UTC midnight, which shifts a
/// day off in any timezone behind UTC. Used to position Roadmap bars in a
/// day-pixel-width grid.
public enum ISODate {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    public static func parse(_ value: String) -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.year = parts.count > 0 ? parts[0] : 1970
        components.month = parts.count > 1 ? parts[1] : 1
        components.day = parts.count > 2 ? parts[2] : 1
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    public static func daysBetween(_ from: String, _ to: String) -> Int {
        let fromDate = calendar.startOfDay(for: parse(from))
        let toDate = calendar.startOfDay(for: parse(to))
        return calendar.dateComponents([.day], from: fromDate, to: toDate).day ?? 0
    }

    public static func addDays(_ value: String, _ days: Int) -> String {
        let date = calendar.date(byAdding: .day, value: days, to: parse(value)) ?? parse(value)
        return format(date)
    }

    public static func today() -> String {
        format(Date())
    }

    private static func format(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }
}
