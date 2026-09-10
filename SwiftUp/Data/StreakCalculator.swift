import Foundation

enum StreakCalculator {
    /// `lastCompletedDate`/`today` are `"yyyy-MM-dd"` local-calendar-day strings (same format as
    /// `DailyEdition.todayKey`). A freeze forgives exactly one missed day; every 7th consecutive
    /// streak day grants one back, capped at 3 banked.
    static func apply(
        lastCompletedDate: String?, streakDays: Int, freezesAvailable: Int, today: String
    ) -> (streakDays: Int, freezesAvailable: Int) {
        guard let lastCompletedDate, let gap = daysBetween(lastCompletedDate, today), gap > 0 else {
            // No prior completion: today starts streak day 1. Same-day or unparseable/negative gap: no-op.
            return lastCompletedDate == nil ? (1, freezesAvailable) : (streakDays, freezesAvailable)
        }
        switch gap {
        case 1:
            return grow(streakDays: streakDays, freezesAvailable: freezesAvailable)
        case 2 where freezesAvailable > 0:
            return grow(streakDays: streakDays, freezesAvailable: freezesAvailable - 1)
        default:
            return (1, freezesAvailable)
        }
    }

    private static func grow(streakDays: Int, freezesAvailable: Int) -> (Int, Int) {
        let newStreak = streakDays + 1
        let freezes = newStreak % 7 == 0 ? min(freezesAvailable + 1, 3) : freezesAvailable
        return (newStreak, freezes)
    }

    private static func daysBetween(_ start: String, _ end: String) -> Int? {
        guard let startDate = dateFormatter.date(from: start), let endDate = dateFormatter.date(from: end) else {
            return nil
        }
        // The calendar doing the day arithmetic must sit in the same timezone the formatter parsed
        // in (UTC). Left on the device's timezone, a DST transition makes the 24h between two
        // consecutive UTC midnights read as 23h (gap 0) or 25h — miscounting real streak gaps.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = dateFormatter.timeZone
        return calendar.dateComponents([.day], from: startDate, to: endDate).day
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
