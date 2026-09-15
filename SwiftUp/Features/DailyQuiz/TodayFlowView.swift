import SwiftUI

struct TodayFlowView: View {
    enum Stage { case entry, question, summary, editions }

    @Environment(QuestionRepository.self) private var questionRepo
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(AuthRepository.self) private var authRepo
    @State private var stage: Stage = .entry
    @State private var session: QuizSession?          // today's real quiz — unchanged meaning
    @State private var practiceSession: QuizSession?   // a redo in progress, if any
    var adPresenter: RewardedAdPresenting = NoOpAdPresenter()

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
                        if let practiceSession {
                            QuizQuestionView(session: practiceSession, onAdvance: advancePractice)
                        } else if let session {
                            QuizQuestionView(session: session, onAdvance: advance)
                        }
                    case .summary:
                        if let session {
                            QuizSummaryView(session: session, onDone: { stage = .editions })
                        }
                    case .editions:
                        QuizEditionsView(
                            todayXPEarned: session?.totalXPEarned ?? 0,
                            onSelectDay: startReplay,
                            onDoneForToday: finish
                        )
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
    /// might never make. Only ever runs for `session` (today's real quiz) — `practiceSession`
    /// never reaches this method (see `advancePractice`).
    private func recordCompletion() {
        guard let session, let uid = authRepo.currentUser?.uid else { return }
        Task { await questionRepo.recordAnswered(session.questions, for: uid) }
        Task { await profileRepo.recordCompletion(session, for: uid) }
    }

    /// Starts a practice redo of `dateKey`, gated on the ad seam. A `nil` past quiz (the date was
    /// never seeded) or a declined ad both quietly no-op — `stage` stays `.editions`, matching the
    /// spec's "no error UI for either case" (design §9).
    private func startReplay(for dateKey: String) {
        adPresenter.presentAd { completed in
            guard completed else { return }
            Task {
                guard let doc = await questionRepo.fetchPastQuiz(for: dateKey) else { return }
                practiceSession = QuizSession(
                    questions: doc.questions(for: questionRepo.effectiveLevel), isPractice: true
                )
                stage = .question
            }
        }
    }

    /// The practice-redo counterpart to `advance()` — deliberately never calls `recordCompletion()`
    /// or shows a summary screen: a redo's result is not persisted anywhere and does not affect XP,
    /// accuracy, or streak (see `QuizSession.isPractice`'s doc comment).
    private func advancePractice() {
        practiceSession?.advance()
        if practiceSession?.isFinished == true {
            practiceSession = nil
            stage = .editions
        }
    }

    private func finish() {
        session = nil
        practiceSession = nil   // the .question stage prefers practiceSession — never leave a stale one
        stage = .entry
    }
}

#Preview {
    TodayFlowView()
        .environment(ProfileRepository.preview())
        .environment(QuestionRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
