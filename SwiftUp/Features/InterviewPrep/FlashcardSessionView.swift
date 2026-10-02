import SwiftUI

struct FlashcardSessionView: View {
    @Environment(InterviewRepository.self) private var repo
    @Environment(AuthRepository.self) private var authRepo
    @State private var session: FlashcardSession
    @State private var pushSummary = false
    var isSessionActive: Binding<Bool>

    init(category: String, level: String, repo: InterviewRepository, isSessionActive: Binding<Bool>) {
        _session = State(initialValue: FlashcardSession(category: category, deck: repo.sessionDeck(in: category, level: level)))
        self.isSessionActive = isSessionActive
    }

    var body: some View {
        Group {
            if let card = session.currentCard {
                VStack(spacing: 0) {
                    if session.isFlipped {
                        back(for: card)
                    } else {
                        progressTicks
                        front(for: card)
                    }
                }
                .padding(24)
            } else {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("Session complete.")
                        .font(Theme.Fonts.body(14))
                        .foregroundStyle(Theme.Colors.neutral700)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
        }
        .background(Theme.Colors.bg)
        // The back's own "← Front" is its only way out (design 11b); the front keeps the system
        // back button for leaving the session.
        .navigationBarBackButtonHidden(session.isFlipped)
        .navigationDestination(isPresented: $pushSummary) {
            SessionSummaryView(session: session, isSessionActive: isSessionActive)
        }
        .onChange(of: session.isComplete) { _, isComplete in
            guard isComplete else { return }
            if let uid = authRepo.currentUser?.uid {
                Task { await repo.recordSession(session.ratings, for: uid) }
            }
            pushSummary = true
        }
    }

    private var progressTicks: some View {
        HStack(spacing: 3) {
            ForEach(Array(session.progress.enumerated()), id: \.offset) { _, rating in
                Rectangle().fill(tickColor(for: rating)).frame(height: 4)
            }
        }
    }

    private var cardCount: String {
        "Card \(String(format: "%02d", session.currentIndex + 1)) / \(String(format: "%02d", session.deck.count))"
    }

    private func tickColor(for rating: FlashcardRating?) -> Color {
        switch rating {
        case .missed: Theme.Colors.accent2
        case .shaky: Theme.Colors.processYellow
        case .nailed: Theme.Colors.text
        case nil: Theme.Colors.neutral300
        }
    }

    private func front(for card: InterviewQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EyebrowLabel(card.category)
                Spacer()
                Text("Card \(session.currentIndex + 1) / \(session.deck.count)")
                    .font(.system(size: 10)).foregroundStyle(Theme.Colors.neutral700)
            }
            .padding(.top, 22)

            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(card.difficulty).font(.system(size: 11))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Theme.Colors.accent100).foregroundStyle(Theme.Colors.accent800)
                    EyebrowLabel(card.category)
                }
                Text(card.prompt).font(Theme.Fonts.heading(28)).padding(.top, 22)
                Text("Answer it out loud, then flip to compare.")
                    .font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral700).padding(.top, 18)
            }
            .padding(24)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.text))
            Spacer()

            HStack(spacing: 12) {
                Button("Skip") { session.skip() }
                    .frame(minHeight: 44)
                Button {
                    session.flip()
                } label: {
                    Text("Flip the card").font(.system(size: 17))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                }
                .background(Theme.Colors.accent).foregroundStyle(Theme.Colors.bg)
            }
        }
    }

    /// Design 11b: "← Front" and the card count over the ticks, then a ruled sheet filling the
    /// space with just the talking points and a link out to the full answer, then the ratings.
    private func back(for card: InterviewQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("← Front") { session.unflip() }
                    .font(Theme.Fonts.body(15))
                    .foregroundStyle(Theme.Colors.accent700)
                Spacer()
                EyebrowLabel(cardCount)
            }
            .frame(minHeight: 44)

            progressTicks
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    EyebrowLabel("The back", color: Theme.Colors.accent700)
                    Spacer()
                    EyebrowLabel(card.category)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        EyebrowLabel("Talking points")
                            .padding(.top, 16)

                        VStack(spacing: 0) {
                            ForEach(Array(card.talkingPoints.enumerated()), id: \.offset) { index, point in
                                HStack(alignment: .firstTextBaseline, spacing: 11) {
                                    Text(String(format: "%02d", index + 1))
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Theme.Colors.accent700)
                                    Text(point)
                                        .font(Theme.Fonts.body(14.5))
                                        .lineSpacing(4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 8)
                                .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
                                .overlay(
                                    index == card.talkingPoints.count - 1
                                        ? Rectangle().fill(Theme.Colors.divider).frame(height: 1) : nil,
                                    alignment: .bottom
                                )
                            }
                        }
                        .padding(.top, 10)

                        NavigationLink {
                            InterviewQuestionDetailView(question: card)
                        } label: {
                            Text("Full answer and follow-ups →")
                                .font(Theme.Fonts.body(13.5))
                                .foregroundStyle(Theme.Colors.accent700)
                        }
                        .padding(.top, 14)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.Colors.bg)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.text, lineWidth: 1))
            .padding(.top, 22)

            EyebrowLabel("How did that go?").padding(.top, 20)
            HStack(spacing: 9) {
                ratingButton("Missed it", fill: Theme.Colors.accent2, foreground: Theme.Colors.bg) { session.rate(.missed) }
                ratingButton("Shaky", fill: Theme.Colors.processYellow, foreground: Theme.Colors.text) { session.rate(.shaky) }
                ratingButton("Nailed it", fill: Theme.Colors.text, foreground: Theme.Colors.bg) { session.rate(.nailed) }
            }
            .padding(.top, 11)
        }
    }

    private func ratingButton(_ title: String, fill: Color, foreground: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15))
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .background(fill).foregroundStyle(foreground)
    }
}

#Preview {
    let repo = InterviewRepository.preview()
    return NavigationStack {
        FlashcardSessionView(category: "Swift fundamentals", level: "Junior", repo: repo, isSessionActive: .constant(true))
    }
    .environment(repo)
    .environment(AuthRepository(isPreview: true, signedIn: true))
}
