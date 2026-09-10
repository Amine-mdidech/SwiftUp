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
}
