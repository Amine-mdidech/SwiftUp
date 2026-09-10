import Testing
import Foundation
@testable import SwiftUp

private func makeQuestion(_ id: String, level: SkillLevel = .junior) -> Question {
    Question(
        id: id, topic: "Test", level: level, format: .multipleChoice,
        prompt: "Prompt \(id)", codeSnippet: nil,
        options: [QuestionOption(id: "A", text: "A"), QuestionOption(id: "B", text: "B")],
        correctOptionID: "A", explanation: "Because.", xp: 15
    )
}

struct QuestionSelectorTests {
    @Test func shouldPromoteWhenEveryQuestionAnswered() {
        let bank = (1...3).map { makeQuestion("q\($0)") }
        let answered: [String: Date] = ["q1": .now, "q2": .now, "q3": .now]
        #expect(QuestionSelector.shouldPromote(bank: bank, answered: answered))
    }

    @Test func shouldNotPromoteWhenSomeUnanswered() {
        let bank = (1...3).map { makeQuestion("q\($0)") }
        let answered: [String: Date] = ["q1": .now]
        #expect(!QuestionSelector.shouldPromote(bank: bank, answered: answered))
    }

    @Test func shouldNotPromoteEmptyBank() {
        #expect(!QuestionSelector.shouldPromote(bank: [], answered: [:]))
    }
}
