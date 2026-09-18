import Foundation

/// The shared pass/fail quiz engine reused by a lesson stage's quiz (after its slides), a
/// track-assessment stage's quiz (no slides), and the grade regrade quiz — only the `questions`
/// array, and the title/callbacks `PathQuizView` is constructed with, differ per use. Unlike
/// `QuizSession` (Daily Quiz), this grants no XP: passing is its own reward (design doc §0/§3).
@Observable
final class PathQuizSession {
    let questions: [PathQuizQuestion]
    private(set) var currentIndex = 0
    private var answers: [String: String] = [:]

    init(questions: [PathQuizQuestion]) {
        self.questions = questions
    }

    var currentQuestion: PathQuizQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var isFinished: Bool { currentIndex >= questions.count }

    var correctCount: Int {
        questions.filter { answers[$0.id] == $0.correctOptionID }.count
    }

    var scorePercent: Int {
        questions.isEmpty ? 0 : (correctCount * 100) / questions.count
    }

    var passed: Bool { scorePercent >= 80 }

    func selectedOptionID(for question: PathQuizQuestion) -> String? {
        answers[question.id]
    }

    func isAnswered(_ question: PathQuizQuestion) -> Bool {
        answers[question.id] != nil
    }

    func selectOption(_ optionID: String) {
        guard let question = currentQuestion, answers[question.id] == nil else { return }
        answers[question.id] = optionID
    }

    func advance() {
        currentIndex += 1
    }

    /// Resets to the first question with every answer cleared, keeping the same `questions`
    /// array — a free retry, never a re-fetch (design doc §0: retries never re-charge XP).
    func retry() {
        currentIndex = 0
        answers = [:]
    }
}
