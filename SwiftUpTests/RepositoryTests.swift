import Testing
import Foundation
import SwiftUI
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
        let originalLevel = repo.profile.level
        let originalName = repo.profile.name

        repo.applyExternalXPBalance(500)

        #expect(repo.profile.xpBalance == 500)
        #expect(repo.profile.xp == originalXP)
        #expect(repo.profile.level == originalLevel)
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

    @Test func pathRepositoryTrackIsClosedOnlyWhenEveryStageIsCompleted() {
        let stages = [
            PathStage(id: "t-s01", order: 1, title: "One", xpCost: 50, kind: .lesson),
            PathStage(id: "t-s02", order: 2, title: "Two", xpCost: 50, kind: .lesson),
            PathStage(id: "t-s03", order: 3, title: "Assessment", xpCost: 400, kind: .assessment),
        ]
        let track = PathTrack(id: "t", grade: .junior, order: 1, title: "Track", stages: stages)
        let repo = PathRepository()

        #expect(repo.isTrackClosed(track) == false)
    }

    @Test func pathRepositoryStageUnlocksOnlyAfterEveryEarlierStageInItsTrackIsDone() {
        let stages = [
            PathStage(id: "t-s01", order: 1, title: "One", xpCost: 50, kind: .lesson),
            PathStage(id: "t-s02", order: 2, title: "Two", xpCost: 50, kind: .lesson),
            PathStage(id: "t-s03", order: 3, title: "Assessment", xpCost: 400, kind: .assessment),
        ]
        let track = PathTrack(id: "t", grade: .junior, order: 1, title: "Track", stages: stages)
        let repo = PathRepository()

        #expect(repo.isStageUnlocked(stages[0], in: track) == true)
        #expect(repo.isStageUnlocked(stages[1], in: track) == false)
        #expect(repo.isStageUnlocked(stages[2], in: track) == false)
    }

    @Test func pathRepositoryTracksForGradeFiltersAndSortsByOrder() {
        let repo = PathRepository.preview(bundle: testBundle)
        let juniorTracks = repo.tracks(for: .junior)
        #expect(juniorTracks.count == 5)
        #expect(juniorTracks.map(\.order) == [1, 2, 3, 4, 5])
        #expect(juniorTracks.allSatisfy { $0.grade == .junior })
    }

    @Test func pathRepositoryFirstTrackInAGradeIsAlwaysReachable() {
        let stages = [PathStage(id: "t1-s01", order: 1, title: "One", xpCost: 50, kind: .lesson)]
        let track1 = PathTrack(id: "t1", grade: .junior, order: 1, title: "One", stages: stages)
        let repo = PathRepository()
        #expect(repo.isTrackReachable(track1) == true)
    }

    @Test func pathRepositorySecondTrackNotReachableBeforeFirstIsClosed() {
        // isTrackReachable looks up sibling tracks via `self.tracks(for:)`, which is `private(set)`
        // and only populated by `load(for:)` — with no test seam (same limitation Sub-project A's
        // isTrackClosed/isStageUnlocked tests already accepted for completedStageIDs). On a fresh,
        // never-loaded repo, `tracks(for:)` returns empty, so `track1` is invisible to `track2`'s
        // reachability check — meaning track2 correctly reads as unreachable, but for the "can't
        // see any predecessor at all" reason rather than "predecessor exists but isn't closed."
        // Both reasons produce the same `false`, which is what this test actually verifies.
        let stage2 = PathStage(id: "t2-s01", order: 1, title: "Two", xpCost: 50, kind: .lesson)
        let track2 = PathTrack(id: "t2", grade: .junior, order: 2, title: "Two", stages: [stage2])
        let repo = PathRepository()
        #expect(repo.isTrackReachable(track2) == false)
    }

    @Test func pathWheelDiagramNodePositionsAreEvenlySpacedStartingAtTwelveOClock() {
        // Calls PathWheelDiagram's own (now internal, @testable-visible) nodePosition(at:)
        // directly rather than maintaining a duplicate copy of the formula, so this test would
        // actually catch a change to the real formula.
        let center = CGPoint(x: 150, y: 150)
        let radius: CGFloat = 110
        let repo = PathRepository()

        func makeTracks(count: Int) -> [PathTrack] {
            (1...count).map { order in
                let stage = PathStage(id: "t\(order)-s01", order: 1, title: "Stage", xpCost: 50, kind: .lesson)
                return PathTrack(id: "t\(order)", grade: .junior, order: order, title: "Track \(order)", stages: [stage])
            }
        }
        func diagram(count: Int) -> PathWheelDiagram {
            PathWheelDiagram(tracks: makeTracks(count: count), grade: .junior, pathRepo: repo, onSelectTrack: { _ in })
        }

        // 5 nodes: node 0 sits directly above center (12 o'clock).
        let fiveNode0 = diagram(count: 5).nodePosition(at: 0)
        #expect(abs(fiveNode0.x - center.x) < 0.001)
        #expect(abs(fiveNode0.y - (center.y - radius)) < 0.001)

        // 4 nodes: node 1 sits 90° clockwise from 12 o'clock, i.e. directly right of center.
        let fourNode1 = diagram(count: 4).nodePosition(at: 1)
        #expect(abs(fourNode1.x - (center.x + radius)) < 0.001)
        #expect(abs(fourNode1.y - center.y) < 0.001)

        // Every node is exactly `radius` from center, for any count.
        for count in [4, 5, 6] {
            let d = diagram(count: count)
            for index in 0..<count {
                let p = d.nodePosition(at: index)
                let distance = sqrt(pow(p.x - center.x, 2) + pow(p.y - center.y, 2))
                #expect(abs(distance - radius) < 0.001)
            }
        }
    }

    @Test func pathStageContentBundledFixtureDecodesAllStagesWithCorrectQuizSizes() throws {
        let bundle = try #require(decodeJSONResource(PathContentBundle.self, filename: "path_content", bundle: testBundle))
        #expect(bundle.stageContent.count == 141)

        let tracks = decodeJSONResource([PathTrack].self, filename: "path_tracks", bundle: testBundle) ?? []
        let allStages = tracks.flatMap(\.stages)
        #expect(allStages.count == 141)

        for stage in allStages {
            let content = try #require(bundle.stageContent.first { $0.stageID == stage.id })
            if stage.kind == .assessment {
                #expect(content.slides.isEmpty)
                #expect(content.quiz.count == 8)
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

    @Test func pathQuizQuestionsAlwaysHaveTheirCorrectOptionIDAmongTheirOwnFourOptions() throws {
        let bundle = try #require(decodeJSONResource(PathContentBundle.self, filename: "path_content", bundle: testBundle))
        for content in bundle.stageContent {
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

    @Test func pathRepositoryIsStageStartedFalseOnAFreshRepository() {
        let stage = PathStage(id: "t-s01", order: 1, title: "One", xpCost: 50, kind: .lesson)
        let repo = PathRepository()
        #expect(repo.isStageStarted(stage) == false)
    }

    @Test func pathRepositoryPromoteGradeIsANoOpAtTheTopGrade() async {
        // `.distinguished.next` is `nil`, so `promoteGrade` returns before touching Firestore —
        // the one branch of this method safely testable without a live network call (same
        // limitation already accepted for every other Firestore write in this project).
        let repo = PathRepository()
        await repo.promoteGrade(from: .distinguished, for: "any-uid")
        #expect(repo.grade == .junior)
    }
}
