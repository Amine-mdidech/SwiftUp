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

    @Test func profileRepositoryLoadsBundledFallback() {
        let repo = ProfileRepository.preview(bundle: testBundle)
        #expect(repo.profile.name == "Maya Reyes")
        #expect(repo.levels.count == 12)
        #expect(repo.achievements.count == 24)
        #expect(repo.topics.count == 12)
    }

    @Test func interviewRepositoryFindsFirstAndNextQuestion() {
        let repo = InterviewRepository(bundle: testBundle)
        #expect(repo.categories.count == 5)
        let first = repo.firstQuestion(in: "Swift fundamentals")
        #expect(first?.id == "iq02")
        if let first {
            #expect(repo.nextQuestion(after: first) != nil)
        }
    }

    @Test func leaderboardRepositoryLoadsEntriesSortedByRank() {
        let repo = LeaderboardRepository(bundle: testBundle)
        #expect(repo.entries.count == 8)
        #expect(repo.entries.first?.rank == 1)
    }
}
