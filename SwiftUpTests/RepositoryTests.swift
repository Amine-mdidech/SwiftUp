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
        #expect(repo.questions.count == 6)
    }

    @Test func interviewRepositoryFirstQuestionRespectsLevel() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        #expect(repo.firstQuestion(in: "Swift fundamentals", level: "Junior")?.id == "sf-j1")
        #expect(repo.firstQuestion(in: "Swift fundamentals", level: "Mid") == nil)
    }

    @Test func interviewRepositoryFirstQuestionAllTiesTowardLowestNonEmptyLevel() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        // "Architecture patterns" has no Junior content, only Mid.
        #expect(repo.firstQuestion(in: "Architecture patterns", level: "All")?.id == "ap-m1")
    }

    @Test func interviewRepositoryNextQuestionStaysWithinSameCategoryAndLevel() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        let first = repo.firstQuestion(in: "Swift fundamentals", level: "Junior")
        #expect(first?.id == "sf-j1")
        let next = first.flatMap(repo.nextQuestion(after:))
        #expect(next?.id == "sf-j2")
    }

    @Test func interviewRepositoryNextQuestionSkipsCategoriesEmptyAtThatLevel() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        // Junior questions only exist in "Swift fundamentals" (2) and "Behavioural" (1); the
        // three categories in between have no Junior content and must be skipped when wrapping.
        let sfJ2 = repo.firstQuestion(in: "Swift fundamentals", level: "Junior")
            .flatMap(repo.nextQuestion(after:))
        #expect(sfJ2?.id == "sf-j2")
        let wrapped = sfJ2.flatMap(repo.nextQuestion(after:))
        #expect(wrapped?.id == "bh-j1")
    }

    @Test func interviewRepositoryNextQuestionSelfLoopsAtTheEndOfTheLastLevelCategory() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        let bhJ1 = repo.firstQuestion(in: "Behavioural", level: "Junior")
        #expect(bhJ1?.id == "bh-j1")
        #expect(bhJ1.flatMap(repo.nextQuestion(after:))?.id == "bh-j1")
    }

    @Test func interviewRepositoryPositionReflectsLevelScopedRank() {
        let repo = InterviewRepository.preview(bundle: testBundle)
        let sfJ2 = repo.firstQuestion(in: "Swift fundamentals", level: "Junior")
            .flatMap(repo.nextQuestion(after:))
        let position = sfJ2.flatMap(repo.position(of:))
        #expect(position?.index == 2)
        #expect(position?.total == 2)
    }

    @Test func leaderboardRepositoryPreviewLoadsEntriesSortedByRank() {
        let repo = LeaderboardRepository.preview(bundle: testBundle)
        #expect(repo.topEntries.count == 8)
        #expect(repo.topEntries.first?.rank == 1)
        #expect(repo.topEntries.first?.totalXP == 640)
    }
}
