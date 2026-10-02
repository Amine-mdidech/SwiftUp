import Foundation

/// The daily quiz masthead's date label, computed from the device clock, plus the shared
/// `yyyy-MM-dd` calendar-day key used to look up today's `dailyQuizzes` document. The edition
/// number itself is not computed on-device — it's read straight from that document
/// (`QuestionRepository.editionNumber`), so it can never disagree with the server's daily content.
enum DailyEdition {
    static func dateLabel(for date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    /// Local calendar-day string (`yyyy-MM-dd`) — the same convention `ProfileRepository` and
    /// `StreakCalculator` use for `dailyCompletions`/streak dates, reused here as the
    /// `dailyQuizzes` document ID so both collections agree on what day "today" is.
    static func todayKey(for date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Parses a `yyyy-MM-dd` calendar-day key (the same convention `todayKey` produces) back into
    /// a `Date` for display formatting. `nil` for a malformed key.
    private static func date(from dateKey: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateKey)
    }

    /// `dateLabel(for:)`'s "Friday, October 2" format for a `yyyy-MM-dd` key — the masthead of a
    /// past day's practice entry screen. Empty string for a malformed key.
    static func dateLabel(forKey dateKey: String, timeZone: TimeZone = .current) -> String {
        guard let parsed = date(from: dateKey, timeZone: timeZone) else { return "" }
        return dateLabel(for: parsed, timeZone: timeZone)
    }

    /// Full weekday name ("Friday") for a `yyyy-MM-dd` key — e.g. the past-editions redo button's
    /// "Sit Friday's" copy. Empty string for a malformed key (never reachable from real streak-day
    /// data, but keeps this a total function for callers).
    static func weekdayName(for dateKey: String, timeZone: TimeZone = .current) -> String {
        guard let parsed = date(from: dateKey, timeZone: timeZone) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: parsed)
    }

    /// Three-letter weekday abbreviation ("Fri") for a `yyyy-MM-dd` key — the compact day-block
    /// labels on the past-editions redo row.
    static func shortWeekdayName(for dateKey: String, timeZone: TimeZone = .current) -> String {
        guard let parsed = date(from: dateKey, timeZone: timeZone) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: parsed)
    }
}
