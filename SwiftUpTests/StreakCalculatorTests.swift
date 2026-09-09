import Testing
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
}
