import Foundation

/// The shared pass/fail quiz engine reused by a class's quiz, a path-assessment class's quiz (no
/// article, straight to the quiz), and the grade regrade quiz — only the `questions` array, and
/// the title/callbacks `LibraryQuizView` is constructed with, differ per use.
@Observable
final class LibraryQuizSession {
    let questions: [LibraryQuizQuestion]
    private(set) var currentIndex = 0
    private var answers: [String: String] = [:]

    init(questions: [LibraryQuizQuestion]) {
        self.questions = questions
    }

    var currentQuestion: LibraryQuizQuestion? {
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
    var isPerfect: Bool { scorePercent == 100 }

    func selectedOptionID(for question: LibraryQuizQuestion) -> String? {
        answers[question.id]
    }

    func isAnswered(_ question: LibraryQuizQuestion) -> Bool {
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
    /// array — a free retry, never a re-fetch.
    func retry() {
        currentIndex = 0
        answers = [:]
    }
}
