import SwiftUI

struct InterviewQuestionDetailView: View {
    @Environment(InterviewRepository.self) private var repo
    @Environment(AuthRepository.self) private var authRepo
    @State var question: InterviewQuestion
    var reviewQueue: [InterviewQuestion]? = nil
    var indexInQueue: Int = 0
    /// The ratings the user actually picked during the session that produced `reviewQueue`, keyed
    /// by question id — read in preference to `repo.reviewState`, which reflects the persisted
    /// server-side batch write. That write is fired-and-forgotten by `FlashcardSessionView` and is
    /// not guaranteed to have landed by the time this screen is reached, so relying on it alone can
    /// silently mislabel the rating shown here and let "Card again" double-write the same document.
    var ratings: [String: FlashcardRating] = [:]
    /// Bound to the flag that presents the whole session flow (`InterviewBankView`'s
    /// `isSessionActive`), so the terminal "Next review" on the last queued card collapses the
    /// entire pushed chain back to the bank in one step — a single-level `dismiss()` only pops back
    /// to `SessionSummaryView`, not the bank, since this view sits three pushes deep.
    var isSessionActive: Binding<Bool> = .constant(true)
    /// Tracks how far "Next review" has advanced past the initial `indexInQueue` — `indexInQueue`
    /// itself is a `var` parameter, not `@State`, so re-reading it after the first tap would always
    /// recompute the same "next" position instead of continuing to advance.
    @State private var currentQueueIndex: Int?

    /// The rating to show/act on for `question` — prefers the in-memory session data (always
    /// correct immediately) over the possibly-not-yet-persisted Firestore-backed `repo.reviewState`.
    private var currentRating: FlashcardRating? {
        ratings[question.id] ?? repo.reviewState[question.id]?.rating
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("← \(question.category)").font(Theme.Fonts.body(15)).foregroundStyle(Theme.Colors.accent700)
                    Spacer()
                    Button {
                        guard let uid = authRepo.currentUser?.uid else { return }
                        Task { await repo.toggleBookmark(question, for: uid) }
                    } label: {
                        Text(repo.isBookmarked(question) ? "★ Bookmarked" : "☆ Bookmark")
                            .font(.system(size: 13)).foregroundStyle(Theme.Colors.accent700)
                    }
                }

                HStack(spacing: 8) {
                    if let rating = currentRating {
                        Text(rating == .missed ? "Missed" : "Shaky")
                            .font(.system(size: 11))
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(rating == .missed ? Theme.Colors.accent2100 : Theme.Colors.accent100)
                            .foregroundStyle(rating == .missed ? Theme.Colors.accent2800 : Theme.Colors.accent800)
                    } else {
                        Text(question.difficulty)
                            .font(.system(size: 11))
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(Theme.Colors.accent100).foregroundStyle(Theme.Colors.accent800)
                    }
                    if let position = repo.position(of: question) {
                        EyebrowLabel("Question \(position.index) of \(position.total)")
                    }
                }
                .padding(.top, 12)

                Text(question.prompt).font(Theme.Fonts.heading(27)).padding(.top, 14)

                EyebrowLabel("Model answer", color: Theme.Colors.accent700).padding(.top, 24)
                Text(question.modelAnswer).font(Theme.Fonts.body(15)).padding(.top, 10)

                EyebrowLabel("Talking points").padding(.top, 22)
                VStack(spacing: 0) {
                    ForEach(Array(question.talkingPoints.enumerated()), id: \.offset) { index, point in
                        RuledRow(showBottomRule: index == question.talkingPoints.count - 1, minHeight: 0, alignment: .top) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.accent700)
                            Text(point).font(Theme.Fonts.body(14))
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.top, 10)

                EyebrowLabel("Follow-ups they ask next").padding(.top, 22)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(question.followUps, id: \.self) { followUp in
                        Text("— \(followUp)").font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral800)
                    }
                }
                .padding(.top, 10)

                if let reviewQueue {
                    reviewActions(queue: reviewQueue)
                }
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }

    /// "Card again" re-rates the current card at its existing rating, refreshing `dueDate` to
    /// tomorrow without relabeling a `.missed` card as `.shaky` (both map to the same +1-day
    /// offset). "Next review" advances the queue in place; on the last card, it pops back to the
    /// bank — "Review now" is a closed loop over exactly this session's weak cards.
    @ViewBuilder
    private func reviewActions(queue: [InterviewQuestion]) -> some View {
        HStack(spacing: 12) {
            Button {
                guard let uid = authRepo.currentUser?.uid else { return }
                let existingRating = currentRating ?? .shaky
                Task { await repo.recordSession([question.id: existingRating], for: uid) }
            } label: {
                Text("Card again").font(.system(size: 15.5))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
            }
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))

            Button {
                let nextIndex = (currentQueueIndex ?? indexInQueue) + 1
                currentQueueIndex = nextIndex
                if nextIndex < queue.count {
                    question = queue[nextIndex]
                } else {
                    isSessionActive.wrappedValue = false
                }
            } label: {
                Text("Next review").font(.system(size: 15.5))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
            }
            .background(Theme.Colors.accent).foregroundStyle(Theme.Colors.bg)
        }
        .padding(.top, 26)
    }
}

#Preview {
    let repo = InterviewRepository.preview()
    return NavigationStack {
        InterviewQuestionDetailView(question: repo.questions[0], reviewQueue: [repo.questions[0]], indexInQueue: 0)
    }
    .environment(repo)
    .environment(AuthRepository(isPreview: true, signedIn: true))
}
