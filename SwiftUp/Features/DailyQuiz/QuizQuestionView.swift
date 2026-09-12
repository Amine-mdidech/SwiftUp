import SwiftUI

struct QuizQuestionView: View {
    let session: QuizSession
    let onAdvance: () -> Void

    var body: some View {
        if let question = session.currentQuestion {
            content(for: question)
        }
    }

    @ViewBuilder
    private func content(for question: Question) -> some View {
        let answered = session.isAnswered(question)
        let selected = session.selectedOptionID(for: question)
        let isCorrect = selected == question.correctOptionID

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Question \(String(format: "%02d", session.currentIndex + 1)) / \(String(format: "%02d", session.questions.count))")
                Spacer()
                Text(question.topic)
                    .font(.system(size: 11))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Theme.Colors.accent100)
                    .foregroundStyle(Theme.Colors.accent800)
            }
            .font(.system(size: 10)).foregroundStyle(Theme.Colors.neutral700)

            HStack(spacing: 4) {
                ForEach(0..<session.questions.count, id: \.self) { i in
                    Rectangle()
                        .fill(tickColor(at: i))
                        .frame(height: 4)
                }
            }
            .padding(.top, 6)

            Text(question.prompt)
                .font(answered ? Theme.Fonts.heading(21) : Theme.Fonts.heading(26))
                .foregroundStyle(answered ? Theme.Colors.neutral700 : Theme.Colors.text)
                .padding(.top, answered ? 24 : 34)

            if let code = question.codeSnippet {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)
                    .padding(.top, 16)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(question.options) { option in
                        optionRow(option, question: question, answered: answered, selected: selected)
                    }
                }
            }
            .padding(.top, question.codeSnippet == nil ? 30 : 16)

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

                Button(action: onAdvance) {
                    Text("Next question")
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
                    Button("Skip", action: onAdvance)
                        .foregroundStyle(Theme.Colors.accent)
                    Spacer()
                    EyebrowLabel("Tap an answer")
                }
            }
        }
        .padding(24)
        .background(Theme.Colors.bg)
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
    private func optionRow(_ option: QuestionOption, question: Question, answered: Bool, selected: String?) -> some View {
        let isSelected = selected == option.id
        let isCorrectOption = option.id == question.correctOptionID
        let showAsCorrect = answered && isCorrectOption
        let showAsWrong = answered && isSelected && !isCorrectOption

        HStack(alignment: .top, spacing: 12) {
            // Reserve the gutter for every row, even when the format's option ids aren't
            // letters (trueFalse: "true"/"false", fillInTheBlank: word ids) — otherwise those
            // rows lose the 14pt indent and their text no longer lines up with lettered options.
            Text(option.id.count == 1 ? option.id.uppercased() : "")
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
}

#Preview("Unanswered") {
    let session = QuizSession(questions: QuestionRepository.preview().todayQuestions)
    return QuizQuestionView(session: session, onAdvance: {})
}

#Preview("Answered") {
    let session = QuizSession(questions: QuestionRepository.preview().todayQuestions)
    session.selectOption("A")
    return QuizQuestionView(session: session, onAdvance: {})
}
