import SwiftUI

struct FlashcardSessionView: View {
    @Environment(InterviewRepository.self) private var repo
    @Environment(AuthRepository.self) private var authRepo
    @State private var session: FlashcardSession
    @State private var pushSummary = false

    init(category: String, level: String, repo: InterviewRepository) {
        _session = State(initialValue: FlashcardSession(category: category, deck: repo.sessionDeck(in: category, level: level)))
    }

    var body: some View {
        Group {
            if let card = session.currentCard {
                VStack(spacing: 0) {
                    progressTicks
                    if session.isFlipped {
                        back(for: card)
                    } else {
                        front(for: card)
                    }
                }
                .padding(24)
            }
        }
        .background(Theme.Colors.bg)
        .navigationDestination(isPresented: $pushSummary) {
            SessionSummaryView(session: session)
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

    private func back(for card: InterviewQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                EyebrowLabel("Talking points")
                VStack(spacing: 0) {
                    ForEach(Array(card.talkingPoints.enumerated()), id: \.offset) { index, point in
                        RuledRow(showBottomRule: index == card.talkingPoints.count - 1, minHeight: 0) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.accent700)
                            Text(point).font(Theme.Fonts.body(14))
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.top, 10)
            }
            .padding(20)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.text))
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
                .frame(maxWidth: .infinity).padding(.vertical, 15)
        }
        .background(fill).foregroundStyle(foreground)
    }
}

#Preview {
    let repo = InterviewRepository.preview()
    return NavigationStack {
        FlashcardSessionView(category: "Swift fundamentals", level: "Junior", repo: repo)
    }
    .environment(repo)
    .environment(AuthRepository(isPreview: true, signedIn: true))
}
