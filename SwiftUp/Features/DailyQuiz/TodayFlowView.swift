import SwiftUI

struct TodayFlowView: View {
    enum Stage { case entry, question, summary }

    @Environment(QuestionRepository.self) private var questionRepo
    @State private var stage: Stage = .entry
    @State private var session: QuizSession?

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .entry:
                    DailyQuizEntryView(onBegin: startQuiz)
                case .question:
                    if let session {
                        QuizQuestionView(session: session, onAdvance: advance)
                    }
                case .summary:
                    if let session {
                        QuizSummaryView(session: session, onDone: finish)
                    }
                }
            }
        }
    }

    private func startQuiz() {
        session = QuizSession(questions: questionRepo.todayQuestions)
        stage = .question
    }

    private func advance() {
        session?.advance()
        if session?.isFinished == true {
            stage = .summary
        }
    }

    private func finish() {
        session = nil
        stage = .entry
    }
}

#Preview {
    TodayFlowView()
        .environment(ProfileRepository())
        .environment(QuestionRepository.preview())
}
