import Testing
import Foundation
@testable import SwiftUp

private func definition(_ id: String, kind: String, topic: String? = nil, minAccuracy: Int? = nil, minAnswered: Int? = nil, count: Int? = nil, days: Int? = nil) -> AchievementDefinition {
    AchievementDefinition(
        id: id, title: "Title \(id)", detail: "Detail", sealKind: .firstSession, xpReward: 50,
        criterion: AchievementCriterion(kind: kind, topic: topic, minAccuracy: minAccuracy, minAnswered: minAnswered, count: count, days: days)
    )
}

private func emptyStats(today: String = "2026-01-15") -> UserStats {
    UserStats(totalXP: 0, streakDays: 0, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: [], today: today)
}

struct AchievementEngineTests {
    @Test func streakEarnedWhenThresholdMet() {
        let stats = UserStats(totalXP: 0, streakDays: 7, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "streak", days: 7)], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func streakInReachBelowThreshold() {
        let stats = UserStats(totalXP: 0, streakDays: 3, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "streak", days: 7)], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .inReach)
        #expect(result.first?.progressCurrent == 3)
        #expect(result.first?.progressTarget == 7)
    }

    @Test func lockedWithNoProgress() {
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "streak", days: 7)], stats: emptyStats(), earnedAt: [:])
        #expect(result.first?.status == .locked)
    }

    @Test func totalAnsweredEarned() {
        let stats = UserStats(totalXP: 0, streakDays: 0, totalQuestionsAnswered: 100, perfectDayCount: 0, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "totalAnswered", count: 100)], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func perfectDaysEarned() {
        let stats = UserStats(totalXP: 0, streakDays: 0, totalQuestionsAnswered: 0, perfectDayCount: 10, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "perfectDays", count: 10)], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func topicMasteryEarnedWhenAccuracyAndCountMet() {
        let stats = UserStats(totalXP: 0, streakDays: 0, totalQuestionsAnswered: 40, perfectDayCount: 0, topicStats: ["Concurrency": (correct: 36, total: 40)], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "topicMastery", topic: "Concurrency", minAccuracy: 90, minAnswered: 40)], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func topicMasteryNotEarnedWhenCountTooLow() {
        // 100% accuracy but only 5 answered, needs 40. Progress must report the answered-count
        // gap (5 of 40), not the already-satisfied accuracy constraint (100 of 90) — otherwise the
        // progress bar would read as maxed-out on an unearned achievement (regression: see
        // AchievementEngine.evaluateCriterion's "topicMastery" case).
        let stats = UserStats(totalXP: 0, streakDays: 0, totalQuestionsAnswered: 5, perfectDayCount: 0, topicStats: ["Concurrency": (correct: 5, total: 5)], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "topicMastery", topic: "Concurrency", minAccuracy: 90, minAnswered: 40)], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .inReach)
        #expect(result.first?.progressCurrent == 5)
        #expect(result.first?.progressTarget == 40)
    }

    @Test func perfectWeekEarnedWithSixOfSevenGoodDays() {
        let recent: [(date: String, correctCount: Int)] = [
            ("2026-01-09", 5), ("2026-01-10", 4), ("2026-01-11", 5), ("2026-01-12", 2),
            ("2026-01-13", 4), ("2026-01-14", 5), ("2026-01-15", 5),
        ]
        let stats = UserStats(totalXP: 0, streakDays: 0, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: recent, today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "perfectWeek")], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func perfectWeekNotEarnedWithOnlyFiveGoodDays() {
        // Only 5 of the last 7 calendar days have a good (>=4/5) completion — 2026-01-10 and
        // 2026-01-15 (today) both have no entry at all — below the "6 of 7" threshold.
        let recent: [(date: String, correctCount: Int)] = [
            ("2026-01-09", 5), ("2026-01-11", 5), ("2026-01-12", 5),
            ("2026-01-13", 5), ("2026-01-14", 5),
        ]
        let stats = UserStats(totalXP: 0, streakDays: 0, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: recent, today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "perfectWeek")], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .locked)
    }

    @Test func perfectMonthEarnedForEveryDaySoFar() {
        let recent: [(date: String, correctCount: Int)] = [
            ("2026-01-01", 5), ("2026-01-02", 4), ("2026-01-03", 5),
        ]
        let stats = UserStats(totalXP: 0, streakDays: 0, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: recent, today: "2026-01-03")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "perfectMonth")], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func onboardedEarnedAfterFirstAnswer() {
        let stats = UserStats(totalXP: 0, streakDays: 0, totalQuestionsAnswered: 5, perfectDayCount: 0, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "onboarded")], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func unbuildableAlwaysLockedRegardlessOfStats() {
        let stats = UserStats(totalXP: 999_999, streakDays: 999, totalQuestionsAnswered: 999_999, perfectDayCount: 999, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "unbuildable")], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .locked)
        #expect(result.first?.progressCurrent == nil)
    }

    @Test func earnedDateDisplayComesFromEarnedAtMap() {
        let stats = UserStats(totalXP: 0, streakDays: 7, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 7
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "streak", days: 7)], stats: stats, earnedAt: ["a1": date])
        #expect(result.first?.status == .earned)
        #expect(result.first?.earnedDateDisplay == "7 Sep")
    }
}
