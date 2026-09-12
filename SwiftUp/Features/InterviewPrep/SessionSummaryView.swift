import SwiftUI

struct SessionSummaryView: View {
    let session: FlashcardSession
    var isSessionActive: Binding<Bool>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: session.category, right: "\(session.deck.count) cards")

                HStack(alignment: .lastTextBaseline, spacing: 20) {
                    PlateNumeral("\(session.nailedCount)", font: Theme.Fonts.heading(76))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("nailed").font(Theme.Fonts.heading(19))
                        Text("\(session.shakyCount) shaky · \(session.missedCount) missed")
                            .font(.system(size: 13.5)).foregroundStyle(Theme.Colors.neutral700)
                    }
                }
                .padding(.top, 26)

                sessionBar.padding(.top, 20)

                if !session.cardsToReview.isEmpty {
                    EyebrowLabel("Review these \(session.cardsToReview.count)", color: Theme.Colors.accent2800)
                        .padding(.top, 30)

                    VStack(spacing: 0) {
                        ForEach(Array(session.cardsToReview.enumerated()), id: \.element.id) { index, card in
                            NavigationLink {
                                InterviewQuestionDetailView(
                                    question: card, reviewQueue: session.cardsToReview, indexInQueue: index,
                                    ratings: session.ratings, isSessionActive: isSessionActive
                                )
                            } label: {
                                RuledRow(showBottomRule: index == session.cardsToReview.count - 1, minHeight: 0) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(card.prompt).font(Theme.Fonts.heading(15))
                                        Text(session.ratings[card.id] == .missed ? "Missed" : "Shaky")
                                            .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
                                    }
                                    Spacer()
                                    Text("→").foregroundStyle(Theme.Colors.accent700)
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 12)
                }

                HStack(spacing: 12) {
                    Button("Back to bank") { isSessionActive.wrappedValue = false }
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))
                    if let first = session.cardsToReview.first {
                        NavigationLink {
                            InterviewQuestionDetailView(
                                question: first, reviewQueue: session.cardsToReview, indexInQueue: 0,
                                ratings: session.ratings, isSessionActive: isSessionActive
                            )
                        } label: {
                            Text("Review now").font(.system(size: 15.5))
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                        }
                        .background(Theme.Colors.accent).foregroundStyle(Theme.Colors.bg)
                    }
                }
                .padding(.top, 26)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
        .navigationBarBackButtonHidden()
    }

    /// Three segments sized proportionally to their share of rated cards — `GeometryReader` sizing
    /// each `Rectangle`'s width directly (the same technique `ThinProgressBar` uses for its single
    /// fill), since `layoutPriority` does not produce flex-ratio-style proportional widths.
    private var sessionBar: some View {
        let total = session.nailedCount + session.shakyCount + session.missedCount
        return GeometryReader { geo in
            HStack(spacing: 3) {
                if total > 0 {
                    Rectangle().fill(Theme.Colors.text)
                        .frame(width: geo.size.width * Double(session.nailedCount) / Double(total))
                    Rectangle().fill(Theme.Colors.processYellow)
                        .frame(width: geo.size.width * Double(session.shakyCount) / Double(total))
                    Rectangle().fill(Theme.Colors.accent2)
                        .frame(width: geo.size.width * Double(session.missedCount) / Double(total))
                }
            }
        }
        .frame(height: 9)
    }
}

#Preview {
    let session = FlashcardSession(
        category: "Architecture patterns",
        deck: InterviewRepository.preview().sessionDeck(in: "Architecture patterns", level: "Mid")
    )
    session.rate(.nailed)
    return NavigationStack { SessionSummaryView(session: session, isSessionActive: .constant(true)) }
}
