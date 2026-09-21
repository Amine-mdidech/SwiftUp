import Testing
import Foundation
@testable import SwiftUp

struct StreakCalculatorTests {
    @Test func firstEverCompletionStartsStreakAtOne() {
        let result = StreakCalculator.apply(lastCompletedDate: nil, streakDays: 0, freezesAvailable: 0, today: "2026-01-10")
        #expect(result.streakDays == 1)
        #expect(result.freezesAvailable == 0)
    }

    @Test func sameDayIsIdempotent() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 1, today: "2026-01-10")
        #expect(result.streakDays == 5)
        #expect(result.freezesAvailable == 1)
    }

    @Test func consecutiveDayGrowsStreak() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 0, today: "2026-01-11")
        #expect(result.streakDays == 6)
        #expect(result.freezesAvailable == 0)
    }

    @Test func crossingSevenGrantsAFreeze() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 6, freezesAvailable: 0, today: "2026-01-11")
        #expect(result.streakDays == 7)
        #expect(result.freezesAvailable == 1)
    }

    @Test func freezesCapAtThree() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 20, freezesAvailable: 3, today: "2026-01-11")
        #expect(result.streakDays == 21)
        #expect(result.freezesAvailable == 3)
    }

    @Test func oneDayGapWithFreezeAvailableConsumesItAndContinuesStreak() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 1, today: "2026-01-12")
        #expect(result.streakDays == 6)
        #expect(result.freezesAvailable == 0)
    }

    @Test func oneDayGapWithNoFreezeResetsStreak() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 0, today: "2026-01-12")
        #expect(result.streakDays == 1)
        #expect(result.freezesAvailable == 0)
    }

    @Test func widerGapResetsStreakEvenWithAFreezeAvailable() {
        // A freeze forgives exactly one missed day — a 2-day gap is too wide for one freeze to cover.
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 1, today: "2026-01-14")
        #expect(result.streakDays == 1)
        #expect(result.freezesAvailable == 1) // not consumed
    }

    // MARK: - Timezone invariant (regression: daysBetween used an unpinned Calendar)

    /// `daysBetween` parses `"yyyy-MM-dd"` with a UTC-pinned `DateFormatter`, so both operands are
    /// UTC midnights. The `Calendar` that then measures the gap must be pinned to the *same*
    /// timezone. Left on the device's timezone (the old bug), a DST-observing zone measures the 24h
    /// between two consecutive UTC midnights as 23h of local wall clock and reports a 0-day gap —
    /// so a genuine next-day completion is mistaken for a same-day repeat and the streak silently
    /// stops growing, once a year, for everyone in that zone.
    ///
    /// Each pair below is two consecutive calendar days that the named zone's clock change makes a
    /// device-local calendar miscount as 0 (verified empirically against tzdata; all are past
    /// dates, so they are historical and stable). The list spans both hemispheres, the most
    /// populated DST zones, and this project's own dev-machine zone, so the test genuinely fails
    /// pre-fix on any machine set to one of them and passes everywhere post-fix.
    @Test func consecutiveDaysAcrossADSTTransitionStillGrowTheStreak() {
        let consecutiveDayPairsSpanningADSTTransition = [
            ("America/New_York", "2025-11-02", "2025-11-03"),
            ("Europe/Paris", "2025-10-26", "2025-10-27"),
            ("Europe/London", "2025-10-26", "2025-10-27"),
            ("Australia/Sydney", "2025-04-05", "2025-04-06"),
            ("America/Santiago", "2025-04-06", "2025-04-07"),
            ("Pacific/Auckland", "2025-04-05", "2025-04-06"),
            ("Africa/Casablanca", "2025-02-23", "2025-02-24"),
        ]
        for (zone, yesterday, today) in consecutiveDayPairsSpanningADSTTransition {
            let result = StreakCalculator.apply(
                lastCompletedDate: yesterday, streakDays: 5, freezesAvailable: 0, today: today
            )
            #expect(result.streakDays == 6, "\(zone): \(yesterday) -> \(today) must read as a 1-day gap")
        }
    }

    /// Machine-independent companion to the test above: it builds the *wrong* (device-local)
    /// calendar explicitly rather than relying on the host machine's timezone, proves the hazard
    /// is still live in current tzdata, and then asserts `StreakCalculator` does not behave that way.
    @Test func dayGapArithmeticIgnoresTheDeviceTimeZone() throws {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        let start = try #require(formatter.date(from: "2025-11-02"))
        let end = try #require(formatter.date(from: "2025-11-05"))

        // What the pre-fix code would have computed on a device set to America/New_York.
        var deviceCalendar = Calendar(identifier: .gregorian)
        deviceCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        #expect(deviceCalendar.dateComponents([.day], from: start, to: end).day == 2,
                "tzdata sanity check: this pair must still be miscounted by a device-local calendar")

        // A true 3-day gap: too wide for one freeze, so the streak resets and the freeze is kept.
        // Under the miscounted 2-day gap it would instead have consumed the freeze and grown to 10.
        let result = StreakCalculator.apply(
            lastCompletedDate: "2025-11-02", streakDays: 9, freezesAvailable: 1, today: "2025-11-05"
        )
        #expect(result.streakDays == 1)
        #expect(result.freezesAvailable == 1)
    }

    // MARK: - dateOffset

    @Test func dateOffsetMovesBackwardAndForward() {
        #expect(StreakCalculator.dateOffset(-1, from: "2026-01-10") == "2026-01-09")
        #expect(StreakCalculator.dateOffset(1, from: "2026-01-10") == "2026-01-11")
        #expect(StreakCalculator.dateOffset(0, from: "2026-01-10") == "2026-01-10")
    }

    @Test func dateOffsetCrossesMonthAndYearBoundaries() {
        #expect(StreakCalculator.dateOffset(-1, from: "2026-01-01") == "2025-12-31")
        #expect(StreakCalculator.dateOffset(-111, from: "2026-01-01") == "2025-09-12")
    }

    // MARK: - frozenDate

    @Test func frozenDateIsNilWhenStreakJustGrows() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 0, today: "2026-01-11")
        #expect(result.frozenDate == nil)
    }

    @Test func frozenDateIsTheDayBeforeTodayWhenAFreezeIsConsumed() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 1, today: "2026-01-12")
        #expect(result.streakDays == 6)
        #expect(result.freezesAvailable == 0)
        #expect(result.frozenDate == "2026-01-11")
    }

    @Test func frozenDateIsNilWhenTheGapIsTooWideToForgive() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 1, today: "2026-01-14")
        #expect(result.frozenDate == nil)
    }

    @Test func frozenDateIsNilOnFirstEverCompletion() {
        let result = StreakCalculator.apply(lastCompletedDate: nil, streakDays: 0, freezesAvailable: 0, today: "2026-01-10")
        #expect(result.frozenDate == nil)
    }

    // MARK: - currentStreak

    @Test func currentStreakStaysAtLastValueWithinOneDayGap() {
        #expect(StreakCalculator.currentStreak(lastCompletedDate: "2026-09-20", streakDays: 12, freezesAvailable: 0, today: "2026-09-21") == 12)
        #expect(StreakCalculator.currentStreak(lastCompletedDate: "2026-09-21", streakDays: 12, freezesAvailable: 0, today: "2026-09-21") == 12)
    }

    @Test func currentStreakForgivesATwoDayGapWithAFreezeBanked() {
        #expect(StreakCalculator.currentStreak(lastCompletedDate: "2026-09-19", streakDays: 12, freezesAvailable: 1, today: "2026-09-21") == 12)
    }

    @Test func currentStreakLapsesToZeroWithoutAFreeze() {
        #expect(StreakCalculator.currentStreak(lastCompletedDate: "2026-09-19", streakDays: 12, freezesAvailable: 0, today: "2026-09-21") == 0)
        #expect(StreakCalculator.currentStreak(lastCompletedDate: "2026-08-01", streakDays: 12, freezesAvailable: 3, today: "2026-09-21") == 0)
    }
}
