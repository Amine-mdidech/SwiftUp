import Testing
import Foundation
import SwiftUI
@testable import SwiftUp

private final class TestBundleMarker {}
private let testBundle = Bundle(for: TestBundleMarker.self)

// `@MainActor` on the whole suite: `ProfileRepository`, `LibraryRepository`, `QuestionRepository`,
// and `InterviewRepository` are all main-actor isolated (their `@Observable` state is read by
// SwiftUI on the main thread), which makes their initializers/static factories/instance methods
// isolated too — and the large majority of tests below touch at least one of them.
@MainActor
struct RepositoryTests {
    @Test func questionRepositoryBundledFallbackLoadsFiveQuestions() {
        let questions = QuestionRepository.loadBundledFallback(bundle: testBundle)
        #expect(questions.count == 5)
    }

    /// `.preview()` seeds the same 5 bundled questions under every level (see its doc comment —
    /// the bundled fallback isn't a real per-level bank), so this only checks that `questions(for:)`
    /// resolves to a non-empty set for all four levels, not that the sets differ.
    @Test func questionRepositoryQuestionsForReturnsTodaysSetForEveryLevel() {
        let repo = QuestionRepository.preview(bundle: testBundle)
        for level in SkillLevel.allCases {
            #expect(repo.questions(for: level).count == 5)
        }
        #expect(repo.todayQuestions.map(\.id) == repo.questions(for: repo.effectiveLevel).map(\.id))
    }

    @Test func profileRepositoryLoadsBundledFallback() {
        let repo = ProfileRepository.preview(bundle: testBundle)
        #expect(repo.profile.name == "Maya Reyes")
        #expect(repo.achievements.count == 23)
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

    @MainActor
    @Test func profileRepositoryApplyExternalXPBalanceUpdatesOnlyXPBalance() {
        let repo = ProfileRepository.preview(bundle: testBundle)
        let originalXP = repo.profile.xp
        let originalName = repo.profile.name

        repo.applyExternalXPBalance(500)

        #expect(repo.profile.xpBalance == 500)
        #expect(repo.profile.xp == originalXP)
        #expect(repo.profile.name == originalName)
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

    @Test func skillLevelDisplayNameRenamesOnlyMid() {
        #expect(SkillLevel.junior.displayName == "Junior")
        #expect(SkillLevel.mid.displayName == "Intermediate")
        #expect(SkillLevel.senior.displayName == "Senior")
        #expect(SkillLevel.distinguished.displayName == "Distinguished")
        // rawValue stays "Mid" — it's what's persisted to Firestore and used in doc IDs.
        #expect(SkillLevel.mid.rawValue == "Mid")
    }

    @Test func libraryPathBundledFixtureDecodesTwentyPathsWithJunior02HandAuthored() throws {
        let paths = decodeJSONResource([LibraryPath].self, filename: "path_tracks", bundle: testBundle) ?? []
        #expect(paths.count == 20)
        let junior02 = try #require(paths.first { $0.id == "junior-02" })
        #expect(junior02.grade == .junior)
        #expect(junior02.title == "Object-oriented Swift")
        #expect(junior02.classes.count == 8)
        #expect(junior02.classes.map(\.xpReward) == [45, 45, 45, 200, 200, 200, 200, 400])
        #expect(junior02.classes.last?.kind == .assessment)
        #expect(junior02.classes.last?.title == "Track assessment")
    }

    @Test func libraryPathSortsClassesByOrderRegardlessOfSourceOrder() throws {
        // Every consumer (isPathSealed, canStartClass, LibraryPathView's class list/progress
        // segments) assumes `classes` is already in play order — this must hold even if the
        // source data (Firestore array order, or a hand-built fixture) isn't already sorted.
        let outOfOrder = [
            LibraryClass(id: "t-s03", order: 3, title: "Three", xpReward: 50, kind: .assessment),
            LibraryClass(id: "t-s01", order: 1, title: "One", xpReward: 50, kind: .lesson),
            LibraryClass(id: "t-s02", order: 2, title: "Two", xpReward: 50, kind: .lesson),
        ]
        let path = LibraryPath(id: "t", grade: .junior, order: 1, title: "Path", summary: "S", classes: outOfOrder)
        #expect(path.classes.map(\.order) == [1, 2, 3])
        #expect(path.classes.map(\.id) == ["t-s01", "t-s02", "t-s03"])

        let decoded = try JSONDecoder().decode(LibraryPath.self, from: Data("""
        {"id":"t2","grade":"Junior","order":2,"title":"Path 2","summary":"S","stages":[
            {"id":"t2-s02","order":2,"title":"Two","xpCost":50,"kind":"lesson"},
            {"id":"t2-s01","order":1,"title":"One","xpCost":50,"kind":"lesson"}
        ]}
        """.utf8))
        #expect(decoded.classes.map(\.id) == ["t2-s01", "t2-s02"])
    }

    @Test func libraryRepositoryPathIsSealedOnlyWhenEveryClassIsCompleted() {
        let classes = [
            LibraryClass(id: "t-s01", order: 1, title: "One", xpReward: 50, kind: .lesson),
            LibraryClass(id: "t-s02", order: 2, title: "Two", xpReward: 50, kind: .lesson),
            LibraryClass(id: "t-s03", order: 3, title: "Assessment", xpReward: 400, kind: .assessment),
        ]
        let path = LibraryPath(id: "t", grade: .junior, order: 1, title: "Path", summary: "S", classes: classes)
        let repo = LibraryRepository()

        #expect(repo.isPathSealed(path) == false)
    }

    @Test func libraryRepositoryOnlyTheAssessmentIsGatedOnEveryOtherClassBeingDone() {
        let classes = [
            LibraryClass(id: "t-s01", order: 1, title: "One", xpReward: 50, kind: .lesson),
            LibraryClass(id: "t-s02", order: 2, title: "Two", xpReward: 50, kind: .lesson),
            LibraryClass(id: "t-s03", order: 3, title: "Assessment", xpReward: 400, kind: .assessment),
        ]
        let path = LibraryPath(id: "t", grade: .junior, order: 1, title: "Path", summary: "S", classes: classes)
        let repo = LibraryRepository()

        // Every non-assessment class is freely startable regardless of what's completed —
        // there's no order gating among them anymore.
        #expect(repo.canStartClass(classes[0], in: path) == true)
        #expect(repo.canStartClass(classes[1], in: path) == true)
        // The assessment is gated until both lesson classes are completed. `completedClassIDs`
        // is `private(set)` and only populated by `load(for:)` (no test seam, same limitation
        // this file already accepts elsewhere for Firestore-backed state), so on a fresh repo
        // it correctly reads as not yet reachable.
        #expect(repo.canStartClass(classes[2], in: path) == false)
    }

    @Test func libraryRepositoryPathsForGradeFiltersAndSortsByOrder() {
        let repo = LibraryRepository.preview(bundle: testBundle)
        let juniorPaths = repo.paths(for: .junior)
        #expect(juniorPaths.count == 5)
        #expect(juniorPaths.map(\.order) == [1, 2, 3, 4, 5])
        #expect(juniorPaths.allSatisfy { $0.grade == .junior })
    }

    @Test func libraryContentBundledFixtureDecodesAllClassesWithCorrectQuizSizes() throws {
        let bundle = try #require(decodeJSONResource(LibraryContentBundle.self, filename: "path_content", bundle: testBundle))
        #expect(bundle.classContent.count == 141)

        let paths = decodeJSONResource([LibraryPath].self, filename: "path_tracks", bundle: testBundle) ?? []
        let allClasses = paths.flatMap(\.classes)
        #expect(allClasses.count == 141)

        for libClass in allClasses {
            let content = try #require(bundle.classContent.first { $0.classID == libClass.id })
            if libClass.kind == .assessment {
                #expect(content.slides.isEmpty)
                #expect(content.quiz.count == 10)
            } else {
                #expect(content.slides.count == 4)
                #expect(content.quiz.count == 5)
            }
        }

        #expect(bundle.regradeQuizzes.count == 3)
        #expect(Set(bundle.regradeQuizzes.map(\.grade)) == [.junior, .mid, .senior])
        for quiz in bundle.regradeQuizzes {
            #expect(quiz.questions.count == 10)
        }
    }

    @Test func libraryQuizQuestionsAlwaysHaveTheirCorrectOptionIDAmongTheirOwnFourOptions() throws {
        let bundle = try #require(decodeJSONResource(LibraryContentBundle.self, filename: "path_content", bundle: testBundle))
        for content in bundle.classContent {
            for question in content.quiz {
                #expect(question.options.count == 4)
                #expect(question.options.contains { $0.id == question.correctOptionID })
            }
        }
        for quiz in bundle.regradeQuizzes {
            for question in quiz.questions {
                #expect(question.options.count == 4)
                #expect(question.options.contains { $0.id == question.correctOptionID })
            }
        }
    }

    @Test func libraryRepositoryIsClassStartedFalseOnAFreshRepository() {
        let libClass = LibraryClass(id: "t-s01", order: 1, title: "One", xpReward: 50, kind: .lesson)
        let repo = LibraryRepository()
        #expect(repo.isClassStarted(libClass) == false)
    }

    @Test func libraryRepositoryIsClassPerfectFalseOnAFreshRepository() {
        let libClass = LibraryClass(id: "t-s01", order: 1, title: "One", xpReward: 50, kind: .lesson)
        let repo = LibraryRepository()
        #expect(repo.isClassPerfect(libClass) == false)
    }

    @Test func libraryRepositoryPromoteGradeIsANoOpAtTheTopGrade() async {
        // `.distinguished.next` is `nil`, so `promoteGrade` returns before touching Firestore —
        // the one branch of this method safely testable without a live network call (same
        // limitation already accepted for every other Firestore write in this project). Grade
        // promotion is unrelated to Library access now — it's a separate status ladder.
        let repo = LibraryRepository()
        await repo.promoteGrade(from: .distinguished, for: "any-uid")
        #expect(repo.grade == .junior)
    }

    @Test func libraryQuizSessionScorePercentAndPassedBoundary() {
        func question(_ id: String) -> LibraryQuizQuestion {
            LibraryQuizQuestion(
                id: id, prompt: "P",
                options: [QuestionOption(id: "A", text: "Correct answer"), QuestionOption(id: "B", text: "Incorrect answer 1")],
                correctOptionID: "A",
                explanation: "Explanation."
            )
        }
        let questions = (1...5).map { question("q\($0)") }
        let session = LibraryQuizSession(questions: questions)

        for _ in 0..<4 {
            session.selectOption("A")   // correct
            session.advance()
        }
        session.selectOption("B")   // wrong, 5th question
        session.advance()

        #expect(session.isFinished == true)
        #expect(session.correctCount == 4)
        #expect(session.scorePercent == 80)
        #expect(session.passed == true)
        #expect(session.isPerfect == false)
    }

    @Test func libraryQuizSessionPerfectScoreRequiresEveryQuestionCorrect() {
        func question(_ id: String) -> LibraryQuizQuestion {
            LibraryQuizQuestion(
                id: id, prompt: "P",
                options: [QuestionOption(id: "A", text: "Correct answer"), QuestionOption(id: "B", text: "Incorrect answer 1")],
                correctOptionID: "A",
                explanation: "Explanation."
            )
        }
        let questions = (1...5).map { question("q\($0)") }
        let session = LibraryQuizSession(questions: questions)

        for _ in 0..<5 {
            session.selectOption("A")
            session.advance()
        }

        #expect(session.scorePercent == 100)
        #expect(session.passed == true)
        #expect(session.isPerfect == true)
    }

    @Test func libraryQuizSessionBelowEightyPercentFails() {
        func question(_ id: String) -> LibraryQuizQuestion {
            LibraryQuizQuestion(
                id: id, prompt: "P",
                options: [QuestionOption(id: "A", text: "Correct answer"), QuestionOption(id: "B", text: "Incorrect answer 1")],
                correctOptionID: "A",
                explanation: "Explanation."
            )
        }
        let questions = (1...5).map { question("q\($0)") }
        let session = LibraryQuizSession(questions: questions)

        session.selectOption("A"); session.advance()
        session.selectOption("A"); session.advance()
        session.selectOption("A"); session.advance()
        session.selectOption("B"); session.advance()
        session.selectOption("B"); session.advance()

        #expect(session.scorePercent == 60)
        #expect(session.passed == false)
        #expect(session.isPerfect == false)
    }

    @Test func libraryQuizSessionRetryResetsAnswersButKeepsTheSameQuestions() {
        func question(_ id: String) -> LibraryQuizQuestion {
            LibraryQuizQuestion(id: id, prompt: "P", options: [QuestionOption(id: "A", text: "Correct answer")], correctOptionID: "A", explanation: "Explanation.")
        }
        let questions = [question("q1"), question("q2")]
        let session = LibraryQuizSession(questions: questions)

        session.selectOption("A"); session.advance()
        session.selectOption("A"); session.advance()
        #expect(session.isFinished == true)

        session.retry()

        #expect(session.isFinished == false)
        #expect(session.currentIndex == 0)
        #expect(session.isAnswered(questions[0]) == false)
        #expect(session.questions.count == 2)
    }
}
