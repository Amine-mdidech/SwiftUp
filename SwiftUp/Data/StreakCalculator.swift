import Foundation

enum StreakCalculator {
    /// `lastCompletedDate`/`today` are `"yyyy-MM-dd"` local-calendar-day strings (same format as
    /// `QuestionSelector.todaySeed`'s date component). A freeze forgives exactly one missed day;
    /// every 7th consecutive streak day grants one back, capped at 3 banked.
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
        return Calendar(identifier: .gregorian).dateComponents([.day], from: startDate, to: endDate).day
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
