import Testing
import Foundation
@testable import SwiftUp

struct NotificationPlannerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// 2026-10-14 is a Wednesday.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func plan(
        at now: Date, preferences: NotificationPreferences = NotificationPreferences(),
        completedToday: Bool = false, streakDays: Int = 0
    ) -> [PlannedNotification] {
        NotificationPlanner.plan(
            now: now, calendar: calendar, preferences: preferences,
            completedToday: completedToday, streakDays: streakDays
        )
    }

    @Test func dailyReminderIncludesTodayWhenQuizIsOpen() {
        let daily = plan(at: date(14, 6)).filter { $0.id.hasPrefix("daily.") }
        #expect(daily.count == 14)
        #expect(daily.first?.fireDate == date(14, 7, 30))
    }

    @Test func dailyReminderSkipsTodayOnceQuizIsDone() {
        let daily = plan(at: date(14, 6), completedToday: true).filter { $0.id.hasPrefix("daily.") }
        #expect(daily.first?.fireDate == date(15, 7, 30))
    }

    @Test func nothingIsScheduledInThePast() {
        let notes = plan(at: date(14, 12))
        #expect(notes.allSatisfy { $0.fireDate > date(14, 12) })
        #expect(notes.first { $0.id.hasPrefix("daily.") }?.fireDate == date(15, 7, 30))
    }

    @Test func streakAlertTonightWhenQuizIsOpen() {
        let streak = plan(at: date(14, 12), streakDays: 5).filter { $0.id == "streakAtRisk" }
        #expect(streak.map(\.fireDate) == [date(14, 21)])
        #expect(streak.first?.body.contains("5-day streak") == true)
    }

    @Test func streakAlertMovesToTomorrowOnceQuizIsDone() {
        let streak = plan(at: date(14, 12), completedToday: true, streakDays: 5).filter { $0.id == "streakAtRisk" }
        #expect(streak.map(\.fireDate) == [date(15, 21)])
    }

    @Test func noStreakAlertWithoutAStreak() {
        #expect(plan(at: date(14, 12), streakDays: 0).allSatisfy { $0.id != "streakAtRisk" })
    }

    @Test func weeklyEditionLandsOnSundayMornings() {
        let weekly = plan(at: date(14, 12)).filter { $0.id.hasPrefix("weekly.") }
        #expect(weekly.map(\.fireDate) == [date(18, 9), date(25, 9)])
    }

    @Test func disabledPreferencesScheduleNothing() {
        let off = NotificationPreferences(dailyReminder: false, streakAtRisk: false, weeklyEdition: false, quietHours: true)
        #expect(plan(at: date(14, 6), preferences: off, streakDays: 3).isEmpty)
    }

    @Test func outputIsSortedByFireDate() {
        let dates = plan(at: date(14, 6), streakDays: 2).map(\.fireDate)
        #expect(dates == dates.sorted())
    }
}
