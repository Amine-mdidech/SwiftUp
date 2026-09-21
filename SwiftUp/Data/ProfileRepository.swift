import Foundation
import FirebaseFirestore

@Observable
@MainActor
final class ProfileRepository {
    let levels: [LevelInfo]
    private let catalog: [AchievementDefinition]

    private(set) var profile: UserProfile
    private(set) var topics: [TopicAccuracy] = []
    private(set) var achievements: [Achievement] = []
    private(set) var isLoading = false
    private(set) var streakDayRecords: [String: StreakDayState] = [:]
    private var loadedUID: String?

    init(bundle: Bundle = .main) {
        levels = decodeJSONResource([LevelInfo].self, filename: "levels", bundle: bundle) ?? []
        catalog = decodeJSONResource([AchievementDefinition].self, filename: "achievement_catalog", bundle: bundle) ?? []
        profile = Self.defaultProfile(levels: levels)
    }

    /// The single definition of "the empty profile" — used by `init` (before any user has ever
    /// loaded) and by `resetToSignedOutDefaults()` (when a *different* uid is about to load, see
    /// `load(for:)`) so both produce exactly the same zeroed state rather than two copies that
    /// could silently drift apart.
    private static func defaultProfile(levels: [LevelInfo]) -> UserProfile {
        let level = LevelCalculator.level(for: 0, ladder: levels)
        return UserProfile(
            name: "", initials: "", level: level.number, levelTitle: level.title,
            xp: 0, xpBalance: 0, xpForCurrentLevel: level.xpForCurrentLevel, xpForNextLevel: level.xpForNextLevel,
            streakDays: 0, freezesAvailable: 0, freezesTotal: 3,
            answeredCount: 0, accuracyPercent: 0, memberSinceDisplay: ""
        )
    }

    /// Resets per-account state to the same empty state `init` produces — called from `load(for:)`
    /// the moment a *different* uid is about to load, so that if the fetch then fails (offline,
    /// transient error), the previous account's name/XP/level/achievements/streak calendar can't
    /// keep showing under the new account. A successful fetch overwrites this as normal.
    private func resetToSignedOutDefaults() {
        profile = Self.defaultProfile(levels: levels)
        topics = []
        achievements = []
        streakDayRecords = [:]
    }

    /// Synchronously loads bundled fallback content — safe for #Preview, never touches Firestore.
    static func preview(bundle: Bundle = .main) -> ProfileRepository {
        let repo = ProfileRepository(bundle: bundle)
        repo.applyBundledFallback(bundle: bundle)
        return repo
    }

    private func applyBundledFallback(bundle: Bundle) {
        let fallbackProfile = decodeJSONResource(UserProfile.self, filename: "profile", bundle: bundle) ?? profile
        let fallbackTopics = decodeJSONResource([TopicAccuracy].self, filename: "topics", bundle: bundle) ?? []
        let level = LevelCalculator.level(for: fallbackProfile.xp, ladder: levels)
        let stats = UserStats(
            totalXP: fallbackProfile.xp, currentLevel: level.number, streakDays: fallbackProfile.streakDays,
            totalQuestionsAnswered: fallbackProfile.answeredCount, perfectDayCount: 0,
            topicStats: [:], recentCompletions: [], today: DailyEdition.todayKey()
        )
        profile = fallbackProfile
        topics = fallbackTopics
        achievements = AchievementEngine.evaluate(catalog: catalog, stats: stats, earnedAt: [:])
    }

    /// Fetches this user's real profile/XP/streak/topic/achievement state from Firestore.
    ///
    /// On failure the repository keeps whatever state it already holds — the zeroed/empty profile
    /// from `init` on a first-ever load, or the last successfully-loaded real data on a later
    /// reload (better than flashing to zero on a transient error). It deliberately does NOT fall
    /// back to the bundled `profile.json`/`topics.json` persona: that content is a mock and is
    /// indistinguishable from real data to a signed-in user, so it is reserved for `preview()`.
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        if loadedUID != uid {
            resetToSignedOutDefaults()
        }
        loadedUID = uid

        let userRef = Firestore.firestore().collection("users").document(uid)
        // Started before the `do` block and awaited after it, independently of `snapshot`/
        // `recentCompletions`: a failure here must not abort loading the rest of the profile (see
        // doc comment on `streakDayRecords`'s declaration) — it's the one fetch on this screen with
        // no bearing on `profile`/`topics`/`achievements`.
        async let streakDayRecordsResult = Self.fetchStreakDayRecords(uid: uid)
        do {
            async let snapshot = userRef.getDocument()
            async let recentCompletions = Self.fetchRecentCompletions(uid: uid)
            let (resolvedSnapshot, resolvedRecent) = try await (snapshot, recentCompletions)
            apply(snapshot: resolvedSnapshot, recentCompletions: resolvedRecent)
        } catch {
            // Intentionally left as-is — see doc comment above.
        }
        if let resolvedStreakDays = try? await streakDayRecordsResult {
            streakDayRecords = resolvedStreakDays
        }
    }

    /// Records a finished quiz session: computes updated XP/streak/topic-stats/achievements,
    /// writes them to Firestore in one batch, then reflects the result locally immediately
    /// (no re-fetch round trip). Non-blocking on failure — the user is never blocked leaving the
    /// quiz screen; worst case this session's stats are lost and the next completion recomputes
    /// from whatever's actually stored.
    ///
    /// Idempotent per calendar day: a second completion on a day already recorded is a no-op.
    /// Nothing in the UI stops a user replaying the same day's five questions, and without this
    /// guard every replay re-added the full session delta to totalXP / totalQuestionsAnswered /
    /// perfectDayCount / topicStats (only the streak was already same-day idempotent, inside
    /// `StreakCalculator.apply`).
    func recordCompletion(_ session: QuizSession, for uid: String) async {
        guard !session.questions.isEmpty else { return }
        let userRef = Firestore.firestore().collection("users").document(uid)

        do {
            let snapshot = try await userRef.getDocument()
            let today = DailyEdition.todayKey()
            guard snapshot.get("lastCompletedDate") as? String != today else { return }

            let existingRecent = try await Self.fetchRecentCompletions(uid: uid)

            var topicStats = Self.decodeTopicStats(snapshot)
            for question in session.questions {
                let wasCorrect = session.selectedOptionID(for: question) == question.correctOptionID
                var entry = topicStats[question.topic] ?? (correct: 0, total: 0)
                entry.total += 1
                if wasCorrect { entry.correct += 1 }
                topicStats[question.topic] = entry
            }

            let previousStreak = (snapshot.get("streakDays") as? Int) ?? 0
            let previousFreezes = (snapshot.get("freezesAvailable") as? Int) ?? 0
            let previousLastCompleted = snapshot.get("lastCompletedDate") as? String
            let streakResult = StreakCalculator.apply(
                lastCompletedDate: previousLastCompleted, streakDays: previousStreak,
                freezesAvailable: previousFreezes, today: today
            )

            let rawDisplayName = snapshot.get("displayName") as? String
            let displayName = (rawDisplayName?.isEmpty == false) ? rawDisplayName! : "SwiftUp user"

            let newTotalXP = ((snapshot.get("totalXP") as? Int) ?? 0) + session.totalXPEarned
            let previousXPBalance = (snapshot.get("xpBalance") as? Int) ?? ((snapshot.get("totalXP") as? Int) ?? 0)
            let newXPBalance = previousXPBalance + session.totalXPEarned
            let newTotalAnswered = ((snapshot.get("totalQuestionsAnswered") as? Int) ?? 0) + session.questions.count
            let isPerfectDay = session.correctCount == session.questions.count
            let newPerfectDayCount = ((snapshot.get("perfectDayCount") as? Int) ?? 0) + (isPerfectDay ? 1 : 0)
            let level = LevelCalculator.level(for: newTotalXP, ladder: levels)

            var recentCompletions = existingRecent.filter { $0.date != today }
            recentCompletions.append((date: today, correctCount: session.correctCount))

            let stats = UserStats(
                totalXP: newTotalXP, currentLevel: level.number, streakDays: streakResult.streakDays,
                totalQuestionsAnswered: newTotalAnswered, perfectDayCount: newPerfectDayCount,
                topicStats: topicStats, recentCompletions: recentCompletions, today: today
            )

            var earnedAt = Self.decodeEarnedAt(snapshot)
            let evaluatedBeforeNewEarns = AchievementEngine.evaluate(catalog: catalog, stats: stats, earnedAt: earnedAt)
            let newlyEarned = evaluatedBeforeNewEarns.filter { $0.status == .earned && earnedAt[$0.id] == nil }
            let now = Date()
            for achievement in newlyEarned { earnedAt[achievement.id] = now }
            // Credited to Firestore below; the local mirror picks it up on the next load rather
            // than being recomputed here, to keep this fix contained.
            let achievementXPReward = newlyEarned.reduce(0) { $0 + $1.xpReward }

            // Nested (not dotted-path) keys, written with `setData(merge:)` rather than
            // `updateData`: `updateData` fails the whole batch if `users/{uid}` doesn't exist yet,
            // which is reachable when `AuthRepository.ensureUserDocument` never ran or silently
            // failed. Merge-set creates the document if needed, leaves omitted fields untouched,
            // and deep-merges nested maps — so `topicStats`/`earnedAchievementIDs` entries not
            // written here survive, exactly as the dotted paths did.
            var userUpdates: [String: Any] = [
                "totalXP": FieldValue.increment(Int64(session.totalXPEarned + achievementXPReward)),
                "xpBalance": FieldValue.increment(Int64(session.totalXPEarned + achievementXPReward)),
                "totalQuestionsAnswered": FieldValue.increment(Int64(session.questions.count)),
                "perfectDayCount": FieldValue.increment(Int64(isPerfectDay ? 1 : 0)),
                "streakDays": streakResult.streakDays,
                "freezesAvailable": streakResult.freezesAvailable,
                "lastCompletedDate": today,
            ]
            // Never write an empty map: merge-set treats `{}` as "overwrite this nested field".
            if !topicStats.isEmpty {
                userUpdates["topicStats"] = topicStats.mapValues { ["correct": $0.correct, "total": $0.total] }
            }
            if !newlyEarned.isEmpty {
                userUpdates["earnedAchievementIDs"] = newlyEarned.reduce(into: [String: Any]()) {
                    $0[$1.id] = FieldValue.serverTimestamp()
                }
            }

            let batch = Firestore.firestore().batch()
            batch.setData(userUpdates, forDocument: userRef, merge: true)
            let dayRef = userRef.collection("dailyCompletions").document(today)
            batch.setData(["correctCount": session.correctCount, "xpEarned": session.totalXPEarned], forDocument: dayRef)
            if let frozenDate = streakResult.frozenDate {
                let frozenRef = userRef.collection("dailyCompletions").document(frozenDate)
                batch.setData(["frozen": true], forDocument: frozenRef, merge: true)
            }
            try await batch.commit()

            let freezesAvailable = streakResult.freezesAvailable
            profile = Self.buildProfile(
                displayName: displayName,
                createdAt: snapshot.get("createdAt") as? Timestamp,
                freezesAvailable: freezesAvailable, xpBalance: newXPBalance, stats: stats, level: level
            )
            topics = topicStats.map { TopicAccuracy(name: $0.key, accuracyPercent: Self.accuracy($0.value)) }.sorted { $0.name < $1.name }
            achievements = AchievementEngine.evaluate(catalog: catalog, stats: stats, earnedAt: earnedAt)
            streakDayRecords[today] = .done
            if let frozenDate = streakResult.frozenDate {
                streakDayRecords[frozenDate] = .freeze
            }
        } catch {
            // Non-blocking — see doc comment above.
        }
    }

    /// Updates only the in-memory `xpBalance` mirror after `PathRepository.startStage` has
    /// already written the real decrement to Firestore — avoids a full `load(for:)` round trip
    /// just to reflect a balance this repository didn't itself compute (design doc §3).
    func applyExternalXPBalance(_ newBalance: Int) {
        profile = UserProfile(
            name: profile.name, initials: profile.initials, level: profile.level, levelTitle: profile.levelTitle,
            xp: profile.xp, xpBalance: newBalance, xpForCurrentLevel: profile.xpForCurrentLevel, xpForNextLevel: profile.xpForNextLevel,
            streakDays: profile.streakDays, freezesAvailable: profile.freezesAvailable, freezesTotal: profile.freezesTotal,
            answeredCount: profile.answeredCount, accuracyPercent: profile.accuracyPercent, memberSinceDisplay: profile.memberSinceDisplay
        )
    }

    // MARK: - Firestore decode helpers

    private func apply(snapshot: DocumentSnapshot, recentCompletions: [(date: String, correctCount: Int)]) {
        let totalXP = (snapshot.get("totalXP") as? Int) ?? 0
        // Backfill-on-read only (no write here — `load(for:)` is read-only today): a user with
        // `totalXP` but no `xpBalance` yet hasn't spent anything, so their full lifetime total is
        // still spendable. The real backfill-and-persist happens in `recordCompletion` below, the
        // next time this user earns anything.
        let xpBalance = (snapshot.get("xpBalance") as? Int) ?? totalXP
        let totalQuestionsAnswered = (snapshot.get("totalQuestionsAnswered") as? Int) ?? 0
        let perfectDayCount = (snapshot.get("perfectDayCount") as? Int) ?? 0
        let freezesAvailable = (snapshot.get("freezesAvailable") as? Int) ?? 0
        let streakDays = StreakCalculator.currentStreak(
            lastCompletedDate: snapshot.get("lastCompletedDate") as? String,
            streakDays: (snapshot.get("streakDays") as? Int) ?? 0,
            freezesAvailable: freezesAvailable, today: DailyEdition.todayKey()
        )
        let topicStats = Self.decodeTopicStats(snapshot)
        let earnedAt = Self.decodeEarnedAt(snapshot)
        let level = LevelCalculator.level(for: totalXP, ladder: levels)

        let stats = UserStats(
            totalXP: totalXP, currentLevel: level.number, streakDays: streakDays,
            totalQuestionsAnswered: totalQuestionsAnswered, perfectDayCount: perfectDayCount,
            topicStats: topicStats, recentCompletions: recentCompletions, today: DailyEdition.todayKey()
        )

        profile = Self.buildProfile(
            displayName: snapshot.get("displayName") as? String,
            createdAt: snapshot.get("createdAt") as? Timestamp,
            freezesAvailable: freezesAvailable, xpBalance: xpBalance, stats: stats, level: level
        )
        topics = topicStats.map { TopicAccuracy(name: $0.key, accuracyPercent: Self.accuracy($0.value)) }.sorted { $0.name < $1.name }
        achievements = AchievementEngine.evaluate(catalog: catalog, stats: stats, earnedAt: earnedAt)
    }

    private static func buildProfile(
        displayName: String?, createdAt: Timestamp?, freezesAvailable: Int, xpBalance: Int, stats: UserStats,
        level: (number: Int, title: String, xpForCurrentLevel: Int, xpForNextLevel: Int)
    ) -> UserProfile {
        let name = (displayName?.isEmpty == false) ? displayName! : "SwiftUp user"
        return UserProfile(
            name: name, initials: initials(from: name), level: level.number, levelTitle: level.title,
            xp: stats.totalXP, xpBalance: xpBalance, xpForCurrentLevel: level.xpForCurrentLevel, xpForNextLevel: level.xpForNextLevel,
            streakDays: stats.streakDays, freezesAvailable: freezesAvailable, freezesTotal: 3,
            answeredCount: stats.totalQuestionsAnswered, accuracyPercent: overallAccuracy(stats.topicStats),
            memberSinceDisplay: memberSinceDisplay(createdAt)
        )
    }

    private static func initials(from name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    private static func overallAccuracy(_ topicStats: [String: (correct: Int, total: Int)]) -> Int {
        let totalCorrect = topicStats.values.reduce(0) { $0 + $1.correct }
        let totalAnswered = topicStats.values.reduce(0) { $0 + $1.total }
        guard totalAnswered > 0 else { return 0 }
        return Int((Double(totalCorrect) / Double(totalAnswered) * 100).rounded())
    }

    private static func accuracy(_ stat: (correct: Int, total: Int)) -> Int {
        guard stat.total > 0 else { return 0 }
        return Int((Double(stat.correct) / Double(stat.total) * 100).rounded())
    }

    private static func memberSinceDisplay(_ timestamp: Timestamp?) -> String {
        guard let timestamp else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        return "Since \(formatter.string(from: timestamp.dateValue()))"
    }

    private static func decodeTopicStats(_ snapshot: DocumentSnapshot) -> [String: (correct: Int, total: Int)] {
        guard let raw = snapshot.get("topicStats") as? [String: [String: Int]] else { return [:] }
        return raw.mapValues { (correct: $0["correct"] ?? 0, total: $0["total"] ?? 0) }
    }

    private static func decodeEarnedAt(_ snapshot: DocumentSnapshot) -> [String: Date] {
        guard let raw = snapshot.get("earnedAchievementIDs") as? [String: Timestamp] else { return [:] }
        return raw.mapValues { $0.dateValue() }
    }

    private static func fetchRecentCompletions(uid: String) async throws -> [(date: String, correctCount: Int)] {
        let snapshot = try await Firestore.firestore()
            .collection("users").document(uid).collection("dailyCompletions")
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: 31)
            .getDocuments()
        return snapshot.documents.compactMap { doc in
            guard let correctCount = doc.get("correctCount") as? Int else { return nil }
            return (date: doc.documentID, correctCount: correctCount)
        }
    }

    private static func fetchStreakDayRecords(uid: String) async throws -> [String: StreakDayState] {
        let today = DailyEdition.todayKey()
        guard let startDate = StreakCalculator.dateOffset(-111, from: today) else { return [:] }
        let snapshot = try await Firestore.firestore()
            .collection("users").document(uid).collection("dailyCompletions")
            .whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: startDate)
            .getDocuments()
        return snapshot.documents.reduce(into: [:]) { result, doc in
            if (doc.get("correctCount") as? Int) != nil {
                result[doc.documentID] = .done
            } else if doc.get("frozen") as? Bool == true {
                result[doc.documentID] = .freeze
            }
        }
    }

    var earnedAchievements: [Achievement] { achievements.filter { $0.status == .earned } }
    var inReachAchievements: [Achievement] { achievements.filter { $0.status == .inReach } }
    var lockedAchievements: [Achievement] { achievements.filter { $0.status == .locked } }

    /// `count` calendar-day keys ending at `today`, oldest first. Shared by `buildCalendarDays`
    /// (112-day grid) and `buildLastSevenDays` (7-day redo picker) so the offset arithmetic lives in
    /// one place.
    private static func recentDates(before today: String, count: Int) -> [String] {
        (0..<count).compactMap { offset in StreakCalculator.dateOffset(-(count - 1 - offset), from: today) }
    }

    /// The last 112 calendar days as an ordered grid input — oldest first, today last. Factored out
    /// as a static, pure function (rather than inline in a computed property reading `self`) so it's
    /// directly unit-testable without touching Firestore or this class's `private(set)` state.
    static func buildCalendarDays(from records: [String: StreakDayState], today: String) -> [StreakDayState] {
        recentDates(before: today, count: 112).map { records[$0] ?? .missed }
    }

    /// Today + the 6 days before it, oldest first, today last, paired with their state — the pure
    /// core of `lastSevenDays` below (mirrors `buildCalendarDays`), directly unit-testable without
    /// touching Firestore or the device clock.
    static func buildLastSevenDays(from records: [String: StreakDayState], today: String) -> [(date: String, state: StreakDayState)] {
        recentDates(before: today, count: 7).map { ($0, records[$0] ?? .missed) }
    }

    var streakCalendarDays: [StreakDayState] {
        Self.buildCalendarDays(from: streakDayRecords, today: DailyEdition.todayKey())
    }

    /// Today + the 6 days before it, oldest first, today last — for the post-quiz "redo an earlier
    /// day" picker. Unlike `streakCalendarDays`, callers need the date string itself (to know which
    /// day a tap means), not just its state.
    var lastSevenDays: [(date: String, state: StreakDayState)] {
        Self.buildLastSevenDays(from: streakDayRecords, today: DailyEdition.todayKey())
    }
}
