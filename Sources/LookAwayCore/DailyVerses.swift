import Foundation

/// The built-in verse of the day: a fixed list, stepped through one verse per
/// calendar day, so everyone sees the same verse on the same day and nothing
/// depends on a network.
///
/// The list itself, `all`, is generated into `DailyVerses+All.swift` from the
/// Berean Standard Bible by `scripts/generate-daily-verses.swift`.
public enum DailyVerses {
    /// The day the list starts from. Days are counted from here rather than
    /// taken as the day of the year, so a list longer than a year still gets
    /// every verse shown, and the new year carries on instead of restarting.
    static let firstDay = DateComponents(year: 2026, month: 1, day: 1)

    public static func verse(on date: Date, calendar: Calendar = .current) -> Verse {
        all[index(on: date, calendar: calendar)]
    }

    /// Whole calendar days since `firstDay`, wrapped onto the list. Counted
    /// between local midnights so a daylight-saving change never skips or
    /// repeats a day, and wrapped both ways so a clock set before `firstDay`
    /// still lands on a verse.
    static func index(on date: Date, calendar: Calendar) -> Int {
        let start = calendar.date(from: firstDay) ?? date
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)
        ).day ?? 0
        return ((days % all.count) + all.count) % all.count
    }
}
