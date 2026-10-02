import SwiftUI

struct TodayFlowView: View {
    /// `.entry` is today's real quiz and is only ever shown before it's been sat. Once finished,
    /// every redo — today or a past day — goes `.editions` → `.practiceEntry` (pick a grade, or
    /// just confirm when the day has only one set) → `.question` → back to `.editions`.
    enum Stage { case entry, question, summary, editions, practiceEntry }

    @Environment(QuestionRepository.self) private var questionRepo
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(AuthRepository.self) private var authRepo
    @State private var stage: Stage = .entry
    @State private var session: QuizSession?          // today's real quiz — unchanged meaning
    @State private var practiceSession: QuizSession?   // a redo in progress, if any
    @State private var practiceEdition: PracticeEdition? // the day `.practiceEntry` is offering
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
                            onSelectDay: openPracticeEntry
                        )
                    case .practiceEntry:
                        if let practiceEdition {
                            DailyQuizEntryView(
                                practice: practiceEdition,
                                onBegin: { level in startPractice(practiceEdition, level: level) },
                                onBack: { stage = .editions }
                            )
                            // A fresh entry screen per day, so a grade picked for one day doesn't
                            // carry over to the next.
                            .id(practiceEdition.dateKey)
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

    /// Takes the exact grade the entry screen was showing when the user tapped "Begin" — not
    /// `questionRepo.effectiveLevel`, which only catches up once the background
    /// `setLevelOverride` write from a same-session tap completes. Reading through `effectiveLevel`
    /// here would risk starting the *previous* grade's quiz if "Begin" is tapped right after
    /// switching, before that write resolves.
    private func startQuiz(level: SkillLevel) {
        session = QuizSession(questions: questionRepo.questions(for: level))
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

    /// Loads `dateKey`'s quiz and shows its entry screen — nothing starts until the user taps
    /// Begin there. Today comes straight from `questionRepo`; a past day is fetched, and a `nil`
    /// (the date was never seeded) quietly leaves `stage` on `.editions` (design §9: no error UI).
    private func openPracticeEntry(for dateKey: String) {
        if dateKey == DailyEdition.todayKey() {
            practiceEdition = PracticeEdition(
                dateKey: dateKey, edition: questionRepo.editionNumber, questions: questionRepo.questions(for:)
            )
            stage = .practiceEntry
            return
        }
        Task {
            guard let doc = await questionRepo.fetchPastQuiz(for: dateKey) else { return }
            practiceEdition = PracticeEdition(dateKey: dateKey, edition: doc.edition, questions: doc.questions(for:))
            stage = .practiceEntry
        }
    }

    /// Starts the redo, gated on the ad seam. A declined ad quietly leaves the user on the entry
    /// screen.
    private func startPractice(_ edition: PracticeEdition, level: SkillLevel) {
        adPresenter.presentAd { completed in
            guard completed else { return }
            practiceSession = QuizSession(questions: edition.questions(for: level), isPractice: true)
            stage = .question
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
}

#Preview {
    TodayFlowView()
        .environment(ProfileRepository.preview())
        .environment(QuestionRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
