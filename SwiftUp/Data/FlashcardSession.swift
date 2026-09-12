import Foundation

/// Ephemeral per-session state for a flashcard run through one category+level deck — created fresh
/// each time a session starts and discarded when the owning view goes away. Deliberately separate
/// from `InterviewRepository` (which owns durable content/state) so an abandoned session can't leak
/// partial state into it; ratings are only persisted once, in a batch, when the deck is exhausted.
@Observable
final class FlashcardSession {
    let category: String
    let deck: [InterviewQuestion]
    private(set) var currentIndex = 0
    private(set) var isFlipped = false
    private(set) var ratings: [String: FlashcardRating] = [:]

    init(category: String, deck: [InterviewQuestion]) {
        self.category = category
        self.deck = deck
    }

    var currentCard: InterviewQuestion? {
        deck.indices.contains(currentIndex) ? deck[currentIndex] : nil
    }

    var isComplete: Bool { currentIndex >= deck.count }

    /// One entry per deck card, in deck order — nil for a card not yet rated. Drives the front's
    /// progress ticks.
    var progress: [FlashcardRating?] {
        deck.map { ratings[$0.id] }
    }

    func flip() { isFlipped = true }

    /// Records a rating for the current card and advances. No-op past the end of the deck.
    func rate(_ rating: FlashcardRating) {
        guard let card = currentCard else { return }
        ratings[card.id] = rating
        advance()
    }

    /// Advances without recording anything — the front's "Skip".
    func skip() { advance() }

    private func advance() {
        currentIndex += 1
        isFlipped = false
    }

    var nailedCount: Int { ratings.values.filter { $0 == .nailed }.count }
    var shakyCount: Int { ratings.values.filter { $0 == .shaky }.count }
    var missedCount: Int { ratings.values.filter { $0 == .missed }.count }

    /// Cards to review now — missed before shaky, each group in the deck order they were rated in.
    var cardsToReview: [InterviewQuestion] {
        deck.filter { ratings[$0.id] == .missed } + deck.filter { ratings[$0.id] == .shaky }
    }
}
