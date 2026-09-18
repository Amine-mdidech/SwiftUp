import Testing
import Foundation
@testable import SwiftUp

private final class TestBundleMarker {}
private let testBundle = Bundle(for: TestBundleMarker.self)

struct RepositoryTests {
    @Test func questionRepositoryBundledFallbackLoadsFiveQuestions() {
        let questions = QuestionRepository.loadBundledFallback(bundle: testBundle)
        #expect(questions.count == 5)
    }

    // `@MainActor` because `ProfileRepository` is main-actor isolated (its `@Observable` state is
    // read by SwiftUI on the main thread), which makes its static `preview(bundle:)` isolated too.
    @MainActor
    @Test func profileRepositoryLoadsBundledFallback() {
        let repo = ProfileRepository.preview(bundle: testBundle)
        #expect(repo.profile.name == "Maya Reyes")
        #expect(repo.levels.count == 12)
        #expect(repo.achievements.count == 24)
        #expect(repo.topics.count == 12)
    }

    @Test func interviewRepositoryLoadsCategoriesFromBundledFallback() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        #expect(repo.categories.count == 5)
        #expect(repo.questions.count == 150)
    }

    @Test func interviewRepositoryNextQuestionStaysWithinSameCategoryAndLevel() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        let first = repo.sessionDeck(in: "Swift fundamentals", level: "Junior").first
        #expect(first?.id == "sf-j1")
        let next = first.flatMap(repo.nextQuestion(after:))
        #expect(next?.id == "sf-j2")
    }

    @Test func interviewRepositoryNextQuestionWrapsToTheNextCategoryAtTheSameLevel() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        // "Swift fundamentals" is followed by "Architecture patterns" in category order; walking
        // past the last Junior question in the first category must land on the first Junior
        // question of the next one.
        let lastInSwiftFundamentals = repo.sessionDeck(in: "Swift fundamentals", level: "Junior", deckSize: 10).last
        #expect(lastInSwiftFundamentals?.id == "sf-j10")
        let wrapped = lastInSwiftFundamentals.flatMap(repo.nextQuestion(after:))
        #expect(wrapped?.id == "ap-j1")
    }

    @Test func interviewRepositoryNextQuestionSelfLoopsAtTheEndOfTheLastLevelCategory() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        // "Behavioural" is the last category in order — walking past its own last Junior question
        // must wrap back to its own first, not fall off the end of the whole bank.
        let bhJ10 = repo.sessionDeck(in: "Behavioural", level: "Junior", deckSize: 10).last
        #expect(bhJ10?.id == "bh-j10")
        #expect(bhJ10.flatMap(repo.nextQuestion(after:))?.id == "bh-j1")
    }

    @Test func interviewRepositoryResolveFallsBackToBundledWhenDecodedIsEmpty() {
        let resolved = InterviewRepository.resolve(decoded: [], bundle: testBundle)
        #expect(resolved.count == 5)
    }

    @Test func interviewRepositoryResolveKeepsDecodedWhenNonEmpty() {
        let fixture = InterviewRepository.loadBundledFallback(bundle: testBundle)
        let resolved = InterviewRepository.resolve(decoded: fixture, bundle: testBundle)
        #expect(resolved.count == fixture.count)
    }

    @Test func interviewRepositoryPositionReflectsLevelScopedRank() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        let sfJ2 = repo.sessionDeck(in: "Swift fundamentals", level: "Junior", deckSize: 10)[1]
        #expect(sfJ2.id == "sf-j2")
        let position = repo.position(of: sfJ2)
        #expect(position?.index == 2)
        #expect(position?.total == 10)
    }

    @Test func interviewRepositoryStartsWithNoBookmarks() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        #expect(repo.bookmarkedIDs.isEmpty)
        #expect(repo.isBookmarked(repo.questions[0]) == false)
    }

    @Test func sessionDeckTakesFirstNQuestionsAtLevel() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        let deck = repo.sessionDeck(in: "Swift fundamentals", level: "Junior", deckSize: 1)
        #expect(deck.map(\.id) == ["sf-j1"])
    }

    @Test func sessionDeckReturnsFewerThanDeckSizeWhenCategoryHasLess() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        let deck = repo.sessionDeck(in: "Swift fundamentals", level: "Junior", deckSize: 15)
        #expect(deck.count == 10)
    }

    @Test func sessionDeckReturnsEmptyForUnknownCategory() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        #expect(repo.sessionDeck(in: "Nope", level: "All").isEmpty)
    }

    @Test func interviewRepositoryStartsWithNoReviewState() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        #expect(repo.reviewState.isEmpty)
        #expect(repo.hasBeenReviewed(repo.questions[0]) == false)
    }

    @Test func flashcardReviewStateDecodesFromJSON() throws {
        let json = Data("""
        {"rating":"nailed","dueDate":"2026-09-16","reviewCount":2}
        """.utf8)
        let decoded = try JSONDecoder().decode(FlashcardReviewState.self, from: json)
        #expect(decoded.rating == .nailed)
        #expect(decoded.dueDate == "2026-09-16")
        #expect(decoded.reviewCount == 2)
    }

    @Test func dueDateAddsFourDaysForNailedAndOneDayOtherwise() {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 12
        let fixedDate = Calendar.current.date(from: components)!
        #expect(InterviewRepository.dueDate(for: .nailed, from: fixedDate) == "2026-09-16")
        #expect(InterviewRepository.dueDate(for: .shaky, from: fixedDate) == "2026-09-13")
        #expect(InterviewRepository.dueDate(for: .missed, from: fixedDate) == "2026-09-13")
    }

    @Test func leaderboardRepositoryPreviewLoadsEntriesSortedByRank() {
        let repo = LeaderboardRepository.preview(bundle: testBundle)
        #expect(repo.topEntries.count == 8)
        #expect(repo.topEntries.first?.rank == 1)
        #expect(repo.topEntries.first?.totalXP == 640)
    }

    @MainActor
    @Test func profileRepositoryBuildsCalendarDaysOldestFirstWithGapsAsMissed() {
        let records: [String: StreakDayState] = [
            "2026-01-08": .done,
            "2026-01-09": .freeze,
            // 2026-01-10 has no entry — must read as .missed
        ]
        let days = ProfileRepository.buildCalendarDays(from: records, today: "2026-01-10")
        #expect(days.count == 112)
        #expect(days[109] == .done)   // 2026-01-08: 2 days before today, index 111-2
        #expect(days[110] == .freeze) // 2026-01-09: 1 day before today
        #expect(days[111] == .missed) // 2026-01-10: today, not yet completed
        #expect(days[0] == .missed)   // 111 days before today: no record, absent, .missed
    }

    @MainActor
    @Test func profileRepositoryBuildsCalendarDaysIgnoresRecordsOutsideTheWindow() {
        let records: [String: StreakDayState] = [
            "2025-09-20": .freeze, // one day before the window's oldest day (2025-09-21) — must be ignored
        ]
        let days = ProfileRepository.buildCalendarDays(from: records, today: "2026-01-10")
        #expect(days.count == 112)
        #expect(days[0] == .missed) // the window's oldest day (2025-09-21) has no entry of its own
        #expect(!days.contains(.freeze)) // the out-of-window record must not leak into any slot
    }

    @MainActor
    @Test func profileRepositoryBuildsCalendarDaysAllMissedForABrandNewUser() {
        let days = ProfileRepository.buildCalendarDays(from: [:], today: "2026-01-10")
        #expect(days.count == 112)
        #expect(days.allSatisfy { $0 == .missed })
    }

    @MainActor
    @Test func profileRepositoryBuildsLastSevenDaysOldestFirstTodayLastWithGapsAsMissed() {
        let records: [String: StreakDayState] = [
            "2026-01-08": .done,
            "2026-01-09": .freeze,
            // 2026-01-10 (today) intentionally has no entry — a fresh completion never lands before
            // this screen renders (see spec §11).
        ]
        let days = ProfileRepository.buildLastSevenDays(from: records, today: "2026-01-10")
        #expect(days.count == 7)
        #expect(days.map(\.date) == ["2026-01-04", "2026-01-05", "2026-01-06", "2026-01-07", "2026-01-08", "2026-01-09", "2026-01-10"])
        #expect(days[4].state == .done)   // 2026-01-08
        #expect(days[5].state == .freeze) // 2026-01-09
        #expect(days[6].state == .missed) // 2026-01-10, today, no record
        #expect(days[0].state == .missed) // 2026-01-04, no record
    }

    @Test func quizSessionDefaultsToNotPracticeAndStoresExplicitFlag() {
        let question = Question(
            id: "q1", topic: "Swift", level: .junior, format: .multipleChoice, prompt: "?",
            codeSnippet: nil, options: [QuestionOption(id: "A", text: "a")],
            correctOptionID: "A", explanation: "e", xp: 10
        )
        let real = QuizSession(questions: [question])
        #expect(real.isPractice == false)

        let practice = QuizSession(questions: [question], isPractice: true)
        #expect(practice.isPractice == true)
    }

    @Test func skillLevelNextClimbsAllFourGradesThenCeilings() {
        #expect(SkillLevel.junior.next == .mid)
        #expect(SkillLevel.mid.next == .senior)
        #expect(SkillLevel.senior.next == .distinguished)
        #expect(SkillLevel.distinguished.next == nil)
    }

    @Test func skillLevelOnboardingChoicesExcludesDistinguished() {
        #expect(SkillLevel.onboardingChoices == [.junior, .mid, .senior])
    }

    @Test func pathTrackBundledFixtureDecodesTwentyTracksWithJunior02HandAuthored() throws {
        let tracks = decodeJSONResource([PathTrack].self, filename: "path_tracks", bundle: testBundle) ?? []
        #expect(tracks.count == 20)
        let junior02 = try #require(tracks.first { $0.id == "junior-02" })
        #expect(junior02.grade == .junior)
        #expect(junior02.title == "Object-oriented Swift")
        #expect(junior02.stages.count == 8)
        #expect(junior02.stages.map(\.xpCost) == [45, 45, 45, 200, 200, 200, 200, 400])
        #expect(junior02.stages.last?.kind == .assessment)
        #expect(junior02.stages.last?.title == "Track assessment")
    }
}
