import SwiftUI

struct TodayFlowView: View {
    /// The only way back to `.entry` once today's real quiz is finished is
    /// `startReplayAtAnotherDifficulty()`, which also sets `isReplayEntry` — so `.entry` is reached
    /// two different ways, and `startQuiz(level:)` reads that flag to tell them apart: a fresh
    /// landing (never done today's real quiz yet) versus a return trip to pick a different grade to
    /// replay. Every other path from `.editions` (redoing a specific past day via `onSelectDay`)
    /// goes straight to `.question`, bypassing `.entry` entirely.
    enum Stage { case entry, question, summary, editions }

    @Environment(QuestionRepository.self) private var questionRepo
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(AuthRepository.self) private var authRepo
    @State private var stage: Stage = .entry
    @State private var session: QuizSession?          // today's real quiz — unchanged meaning
    @State private var practiceSession: QuizSession?   // a redo in progress, if any
    /// Set by `startReplayAtAnotherDifficulty()` right before it sends `stage` back to `.entry` —
    /// tells `startQuiz(level:)` to build a practice session instead of overwriting today's already
    /// -completed real one. Consumed (reset to `false`) the moment `startQuiz(level:)` reads it.
    @State private var isReplayEntry = false
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
                            onReplayAtAnotherDifficulty: startReplayAtAnotherDifficulty
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

    /// Takes the exact grade the entry screen was showing when the user tapped "Begin" — not
    /// `questionRepo.effectiveLevel`, which only catches up once the background
    /// `setLevelOverride` write from a same-session tap completes. Reading through `effectiveLevel`
    /// here would risk starting the *previous* grade's quiz if "Begin" is tapped right after
    /// switching, before that write resolves.
    ///
    /// Branches on `isReplayEntry` rather than on whether `session` is already set: today's real
    /// quiz can only be started once per calendar day (`.entry` isn't reachable again afterward
    /// except through a replay), so by the time this runs in the non-replay branch, `session` being
    /// non-nil already would mean a bug elsewhere, not a case to special-case around here.
    private func startQuiz(level: SkillLevel) {
        if isReplayEntry {
            isReplayEntry = false
            practiceSession = QuizSession(questions: questionRepo.questions(for: level), isPractice: true)
        } else {
            session = QuizSession(questions: questionRepo.questions(for: level))
        }
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

    /// Sends the user back to the entry screen's grade switcher to replay *today's* already-shared
    /// quiz at a different grade than the one they actually sat — gated on the same ad seam as
    /// `startReplay(for:)`, since it's the same kind of free bonus practice round. A declined ad
    /// quietly no-ops, same as there.
    private func startReplayAtAnotherDifficulty() {
        adPresenter.presentAd { completed in
            guard completed else { return }
            isReplayEntry = true
            stage = .entry
        }
    }
}

#Preview {
    TodayFlowView()
        .environment(ProfileRepository.preview())
        .environment(QuestionRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
