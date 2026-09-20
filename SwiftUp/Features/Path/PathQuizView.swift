import SwiftUI

/// The shared quiz UI for a lesson stage's quiz, a track-assessment stage's quiz, and the grade
/// regrade quiz (`PathRegradeQuizView`). `title` labels the header (a stage/track title, or
/// "Regrade quiz"). `onPassed` fires once, the moment a passing score is reached, to record
/// progress (`PathRepository.completeStage`/`.promoteGrade` — the caller decides which).
/// `onFinished` fires only when the user taps "Back to <title>" after passing, popping back to
/// wherever this view was pushed from.
struct PathQuizView: View {
    let title: String
    let onPassed: () async -> Void
    let onFinished: () -> Void

    @State private var session: PathQuizSession

    init(title: String, questions: [PathQuizQuestion], onPassed: @escaping () async -> Void, onFinished: @escaping () -> Void) {
        self.title = title
        self.onPassed = onPassed
        self.onFinished = onFinished
        _session = State(initialValue: PathQuizSession(questions: questions))
    }

    var body: some View {
        Group {
            if session.isFinished {
                resultContent
            } else if let question = session.currentQuestion {
                questionContent(question)
            }
        }
        .padding(24)
        .background(Theme.Colors.bg)
        .navigationBarBackButtonHidden()
    }

    @ViewBuilder
    private func questionContent(_ question: PathQuizQuestion) -> some View {
        let answered = session.isAnswered(question)
        let selected = session.selectedOptionID(for: question)
        let isCorrect = selected == question.correctOptionID

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.Colors.neutral700)
                Spacer()
                Text("Question \(String(format: "%02d", session.currentIndex + 1)) / \(String(format: "%02d", session.questions.count))")
                    .font(.system(size: 10)).foregroundStyle(Theme.Colors.neutral700)
            }

            HStack(spacing: 4) {
                ForEach(0..<session.questions.count, id: \.self) { i in
                    Rectangle().fill(tickColor(at: i)).frame(height: 4)
                }
            }
            .padding(.top, 6)

            Text(question.prompt)
                .font(answered ? Theme.Fonts.heading(21) : Theme.Fonts.heading(26))
                .foregroundStyle(answered ? Theme.Colors.neutral700 : Theme.Colors.text)
                .padding(.top, answered ? 24 : 34)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(question.options) { option in
                        optionRow(option, question: question, answered: answered, selected: selected)
                    }
                }
            }
            .padding(.top, 30)

            if answered {
                VStack(alignment: .leading, spacing: 12) {
                    Text(isCorrect ? "Correct." : "Not quite.")
                        .font(Theme.Fonts.heading(20))
                        .foregroundStyle(isCorrect ? Theme.Colors.accent700 : Theme.Colors.accent2800)
                    Text(question.explanation)
                        .font(Theme.Fonts.body(14.5))
                        .foregroundStyle(Theme.Colors.neutral800)
                }
                .padding(.top, 20)

                Button(action: { session.advance() }) {
                    Text(session.currentIndex == session.questions.count - 1 ? "See results" : "Next question")
                        .font(Theme.Fonts.heading(17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
                .padding(.top, 20)
            } else {
                Spacer(minLength: 20)
                HStack {
                    Spacer()
                    EyebrowLabel("Tap an answer")
                }
            }
        }
    }

    private func tickColor(at index: Int) -> Color {
        guard index <= session.currentIndex else { return Theme.Colors.neutral300 }
        guard index < session.currentIndex || session.isAnswered(session.questions[index]) else {
            return Theme.Colors.text
        }
        let q = session.questions[index]
        guard let picked = session.selectedOptionID(for: q) else { return Theme.Colors.text }
        return picked == q.correctOptionID ? Theme.Colors.accent : Theme.Colors.accent2
    }

    @ViewBuilder
    private func optionRow(_ option: QuestionOption, question: PathQuizQuestion, answered: Bool, selected: String?) -> some View {
        let isSelected = selected == option.id
        let isCorrectOption = option.id == question.correctOptionID
        let showAsCorrect = answered && isCorrectOption
        let showAsWrong = answered && isSelected && !isCorrectOption

        HStack(alignment: .top, spacing: 12) {
            Text(option.id)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(showAsCorrect ? Theme.Colors.accent700 : (showAsWrong ? Theme.Colors.accent2800 : Theme.Colors.neutral600))
                .frame(width: 14, alignment: .leading)
            Text(option.text)
                .font(Theme.Fonts.body(15.5))
                .foregroundStyle(Theme.Colors.text)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, showAsCorrect || showAsWrong ? 11 : 2)
        .background(showAsCorrect ? Theme.Colors.accent100 : (showAsWrong ? Theme.Colors.accent2100 : Color.clear))
        .opacity(answered && !isSelected && !isCorrectOption ? 0.4 : 1)
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            guard !answered else { return }
            session.selectOption(option.id)
        }
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(session.passed ? "Passed." : "Not yet.")
                .font(Theme.Fonts.heading(30))
            Text("\(session.correctCount) of \(session.questions.count) correct — \(session.scorePercent)%")
                .font(Theme.Fonts.body(15))
                .foregroundStyle(Theme.Colors.neutral800)
                .padding(.top, 12)

            if session.passed {
                Text("80% or higher passes.")
                    .font(Theme.Fonts.body(13))
                    .foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 6)
                Button(action: onFinished) {
                    Text("Back to \(title)")
                        .font(Theme.Fonts.heading(17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
                .padding(.top, 24)
            } else {
                Text("80% or higher passes — try again, it's free.")
                    .font(Theme.Fonts.body(13))
                    .foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 6)
                Button(action: { session.retry() }) {
                    Text("Try again")
                        .font(Theme.Fonts.heading(17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
                .padding(.top, 24)
            }
            Spacer(minLength: 20)
        }
        // Fires exactly once per genuine pass: this branch of the view only exists once
        // `isFinished` is true, and the retry button (the only way `passed` flips back to false)
        // lives in the opposite branch below — so `passed` transitions false -> true at most once
        // per session lifetime before a possible future retry resets it.
        .task(id: session.passed) {
            guard session.isFinished, session.passed else { return }
            await onPassed()
        }
    }
}

#Preview("Unanswered") {
    let questions = [
        PathQuizQuestion(
            id: "q1", prompt: "Which of these is correct?",
            options: [
                QuestionOption(id: "A", text: "Correct answer"),
                QuestionOption(id: "B", text: "Incorrect answer 1"),
                QuestionOption(id: "C", text: "Incorrect answer 2"),
                QuestionOption(id: "D", text: "Incorrect answer 3"),
            ],
            correctOptionID: "A",
            explanation: "This is a placeholder explanation shown after answering."
        )
    ]
    return PathQuizView(title: "Preview stage", questions: questions, onPassed: {}, onFinished: {})
}
