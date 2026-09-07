import Foundation

@Observable
final class QuizSession {
    let questions: [Question]
    private(set) var currentIndex: Int = 0
    private var answers: [String: String] = [:]
    private let startedAt = Date()
    private var finishedAt: Date?

    init(questions: [Question]) {
        self.questions = questions
    }

    var currentQuestion: Question? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var isFinished: Bool { currentIndex >= questions.count }

    var correctCount: Int {
        questions.filter { answers[$0.id] == $0.correctOptionID }.count
    }

    var totalXPEarned: Int {
        let base = questions.reduce(0) { partial, q in
            partial + (answers[q.id] == q.correctOptionID ? q.xp : 0)
        }
        let bonus = (correctCount == questions.count && !questions.isEmpty) ? 25 : 0
        return base + bonus
    }

    var elapsedSeconds: Int {
        Int((finishedAt ?? Date()).timeIntervalSince(startedAt))
    }

    func selectedOptionID(for question: Question) -> String? {
        answers[question.id]
    }

    func isAnswered(_ question: Question) -> Bool {
        answers[question.id] != nil
    }

    func selectOption(_ optionID: String) {
        guard let question = currentQuestion, answers[question.id] == nil else { return }
        answers[question.id] = optionID
    }

    func advance() {
        currentIndex += 1
        if isFinished { finishedAt = Date() }
    }
}
