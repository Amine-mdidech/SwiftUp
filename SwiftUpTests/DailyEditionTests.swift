import Testing
import Foundation
@testable import SwiftUp

struct DailyEditionTests {
    private static let utc = TimeZone(identifier: "UTC")!

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func date(_ yyyyMMdd: String) throws -> Date {
        try #require(Self.utcFormatter.date(from: yyyyMMdd))
    }

    @Test func dateLabelFormatsWeekdayAndDate() throws {
        #expect(DailyEdition.dateLabel(for: try date("2026-09-07"), timeZone: Self.utc) == "Monday, September 7")
        #expect(DailyEdition.dateLabel(for: try date("2026-09-10"), timeZone: Self.utc) == "Thursday, September 10")
    }

    @Test func todayKeyFormatsAsYearMonthDay() throws {
        #expect(DailyEdition.todayKey(for: try date("2026-09-07"), timeZone: Self.utc) == "2026-09-07")
    }

    // MARK: - Timezone invariant

    /// `todayKey` is the document ID used to look up `dailyQuizzes/{date}` — it must reflect the
    /// *local* calendar day (matching what `dateLabel` displays), not get shifted by formatting
    /// in a different zone. A UTC evening instant should still read as the next local day in a
    /// zone ahead of UTC.
    @Test func todayKeyReflectsTheGivenTimeZonesCalendarDay() throws {
        let utcEvening = try date("2026-09-07") // midnight UTC
            .addingTimeInterval(23 * 3600) // 11pm UTC, same UTC day
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo")) // UTC+9 -> already the next day
        #expect(DailyEdition.todayKey(for: utcEvening, timeZone: Self.utc) == "2026-09-07")
        #expect(DailyEdition.todayKey(for: utcEvening, timeZone: tokyo) == "2026-09-08")
    }
}
