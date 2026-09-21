import Foundation

/// Everything AchievementEngine needs to evaluate every criterion kind. Built by ProfileRepository
/// from stored Firestore fields (or bundled fallback data) — never persisted in this shape itself.
struct UserStats {
    let totalXP: Int
    let currentLevel: Int
    let streakDays: Int
    let totalQuestionsAnswered: Int
    let perfectDayCount: Int
    let topicStats: [String: (correct: Int, total: Int)]
    let recentCompletions: [(date: String, correctCount: Int)]   // any order; last ~31 calendar days
    let today: String   // "yyyy-MM-dd"
}

enum AchievementEngine {
    /// `earnedAt` are timestamps for achievements already recorded as earned (from
    /// `users/{uid}.earnedAchievementIDs`) — used only for `earnedDateDisplay`, not for deciding
    /// whether something is newly earned (the caller compares this function's output against
    /// `earnedAt`'s keys to find that).
    static func evaluate(catalog: [AchievementDefinition], stats: UserStats, earnedAt: [String: Date]) -> [Achievement] {
        catalog.map { definition in
            let (isEarned, progress) = evaluateCriterion(definition.criterion, stats: stats)
            let status: AchievementStatus = isEarned ? .earned : ((progress?.current ?? 0) > 0 ? .inReach : .locked)
            return Achievement(
                id: definition.id,
                title: definition.title,
                detail: definition.detail,
                sealKind: definition.sealKind,
                status: status,
                xpReward: definition.xpReward,
                earnedDateDisplay: earnedAt[definition.id].map { displayFormatter.string(from: $0) },
                progressCurrent: status == .earned ? nil : progress?.current,
                progressTarget: status == .earned ? nil : progress?.target
            )
        }
    }

    private static func evaluateCriterion(
        _ criterion: AchievementCriterion, stats: UserStats
    ) -> (earned: Bool, progress: (current: Int, target: Int)?) {
        switch criterion.kind {
        case "streak":
            let target = criterion.days ?? 0
            return (stats.streakDays >= target, (stats.streakDays, target))

        case "totalAnswered":
            let target = criterion.count ?? 0
            return (stats.totalQuestionsAnswered >= target, (stats.totalQuestionsAnswered, target))

        case "perfectDays":
            let target = criterion.count ?? 0
            return (stats.perfectDayCount >= target, (stats.perfectDayCount, target))

        case "topicMastery":
            guard let topic = criterion.topic, let stat = stats.topicStats[topic], stat.total > 0 else {
                return (false, nil)
            }
            let accuracy = Int((Double(stat.correct) / Double(stat.total) * 100).rounded())
            let minAccuracy = criterion.minAccuracy ?? 0
            let minAnswered = criterion.minAnswered ?? 0
            let isEarned = accuracy >= minAccuracy && stat.total >= minAnswered
            // Report whichever constraint is still binding, so the progress bar doesn't read as
            // maxed-out on accuracy alone while the answer-count requirement is nowhere close.
            let progress = accuracy >= minAccuracy ? (min(stat.total, minAnswered), minAnswered) : (accuracy, minAccuracy)
            return (isEarned, progress)

        case "perfectWeek":
            let dates = lastNDates(before: stats.today, count: 7)
            let goodDays = dates.filter { isGoodDay($0, in: stats.recentCompletions) }.count
            return (goodDays >= 6, nil)

        case "perfectMonth":
            let dates = datesSoFarThisMonth(today: stats.today)
            let goodDays = dates.filter { isGoodDay($0, in: stats.recentCompletions) }.count
            return (!dates.isEmpty && goodDays == dates.count, nil)

        case "onboarded":
            return (stats.totalQuestionsAnswered > 0, nil)

        case "level":
            let target = criterion.count ?? 0
            return (stats.currentLevel >= target, (stats.currentLevel, target))

        default: // "unbuildable" and any unrecognized kind
            return (false, nil)
        }
    }

    private static func isGoodDay(_ date: String, in completions: [(date: String, correctCount: Int)]) -> Bool {
        completions.first { $0.date == date }.map { $0.correctCount >= 4 } ?? false
    }

    private static func lastNDates(before today: String, count: Int) -> [String] {
        guard let todayDate = dateFormatter.date(from: today) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = dateFormatter.timeZone
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: todayDate).map(dateFormatter.string(from:))
        }
    }

    private static func datesSoFarThisMonth(today: String) -> [String] {
        guard let todayDate = dateFormatter.date(from: today) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = dateFormatter.timeZone
        guard
            let range = calendar.range(of: .day, in: .month, for: todayDate),
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: todayDate))
        else { return [] }
        return range.compactMap { day in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart), date <= todayDate else {
                return nil
            }
            return dateFormatter.string(from: date)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        return formatter
    }()
}
