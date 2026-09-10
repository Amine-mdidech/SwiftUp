import SwiftUI

struct TodayFlowView: View {
    enum Stage { case entry, question, summary }

    @Environment(QuestionRepository.self) private var questionRepo
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(AuthRepository.self) private var authRepo
    @State private var stage: Stage = .entry
    @State private var session: QuizSession?

    var body: some View {
        NavigationStack {
            Group {
                if questionRepo.isLoading && questionRepo.todayQuestions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.Colors.bg)
                } else {
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
        .task {
            guard let uid = authRepo.currentUser?.uid else { return }
            async let questionsLoad: Void = questionRepo.load(for: uid)
            async let profileLoad: Void = profileRepo.load(for: uid)
            _ = await (questionsLoad, profileLoad)
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
            recordCompletion()
        }
    }

    /// Fired the moment the fifth question is answered, not when the user later dismisses the
    /// summary screen — so XP/streak are written to Firestore even if the user backgrounds or
    /// force-quits the app while looking at the summary, instead of only on a "Done" tap they
    /// might never make.
    private func recordCompletion() {
        guard let session, let uid = authRepo.currentUser?.uid else { return }
        Task { await questionRepo.recordAnswered(session.questions, for: uid) }
        Task { await profileRepo.recordCompletion(session, for: uid) }
    }

    private func finish() {
        session = nil
        stage = .entry
    }
}

#Preview {
    TodayFlowView()
        .environment(ProfileRepository.preview())
        .environment(QuestionRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
