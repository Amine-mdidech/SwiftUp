import Testing
@testable import SwiftUp

private func makeQuestions() -> [Question] {
    (1...5).map { i in
        Question(
            id: "q\(i)", topic: "Topic", level: .junior, format: .multipleChoice,
            prompt: "Prompt \(i)", codeSnippet: nil,
            options: [QuestionOption(id: "A", text: "A"), QuestionOption(id: "B", text: "B")],
            correctOptionID: "A", explanation: "Because.", xp: 15
        )
    }
}

struct QuizSessionTests {
    @Test func startsAtFirstQuestionUnanswered() {
        let session = QuizSession(questions: makeQuestions())
        #expect(session.currentIndex == 0)
        #expect(session.isFinished == false)
        #expect(session.isAnswered(session.currentQuestion!) == false)
    }

    @Test func selectingCorrectOptionCountsTowardScoreAndXP() {
        let session = QuizSession(questions: makeQuestions())
        session.selectOption("A")
        #expect(session.isAnswered(session.currentQuestion!) == true)
        #expect(session.selectedOptionID(for: session.currentQuestion!) == "A")
        session.advance()
        #expect(session.correctCount == 1)
    }

    @Test func secondSelectAfterAnsweringIsIgnored() {
        let session = QuizSession(questions: makeQuestions())
        session.selectOption("A")
        session.selectOption("B")
        #expect(session.selectedOptionID(for: session.currentQuestion!) == "A")
    }

    @Test func advancingPastLastQuestionFinishesSession() {
        let session = QuizSession(questions: makeQuestions())
        for _ in 0..<5 {
            session.selectOption("A")
            session.advance()
        }
        #expect(session.isFinished == true)
        #expect(session.currentQuestion == nil)
        #expect(session.correctCount == 5)
    }

    @Test func perfectScoreEarnsBonusXP() {
        let session = QuizSession(questions: makeQuestions())
        for _ in 0..<5 {
            session.selectOption("A")
            session.advance()
        }
        #expect(session.totalXPEarned == 5 * 15 + 25)
    }

    @Test func imperfectScoreEarnsNoBonus() {
        let session = QuizSession(questions: makeQuestions())
        session.selectOption("B")
        session.advance()
        for _ in 0..<4 {
            session.selectOption("A")
            session.advance()
        }
        #expect(session.totalXPEarned == 4 * 15)
    }
}
