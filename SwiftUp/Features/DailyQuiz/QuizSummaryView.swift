import SwiftUI

struct QuizSummaryView: View {
    @Environment(QuestionRepository.self) private var questionRepo
    let session: QuizSession
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RuledMasthead(left: "\(editionLabel) · closed just now", right: "\(session.elapsedSeconds / 60) min \(session.elapsedSeconds % 60) s")

            HStack(alignment: .bottom, spacing: 22) {
                PlateNumeral("\(session.correctCount)/\(session.questions.count)", font: Theme.Fonts.heading(84))
                VStack(alignment: .leading, spacing: 6) {
                    Text("+\(session.totalXPEarned) xp")
                        .font(Theme.Fonts.heading(22))
                        .foregroundStyle(Theme.Colors.accent700)
                }
            }
            .padding(.top, 34)

            Spacer()

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .background(Theme.Colors.accent)
            .foregroundStyle(Theme.Colors.bg)
        }
        .padding(24)
        .background(Theme.Colors.bg)
    }

    private var editionLabel: String {
        questionRepo.editionNumber.map { "Edition \($0)" } ?? "Edition —"
    }
}

#Preview {
    let questionRepo = QuestionRepository.preview()
    let session = QuizSession(questions: questionRepo.todayQuestions)
    return QuizSummaryView(session: session, onDone: {})
        .environment(questionRepo)
}
