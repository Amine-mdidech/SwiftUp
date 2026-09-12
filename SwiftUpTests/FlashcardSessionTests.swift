import Testing
@testable import SwiftUp

private func makeQuestion(_ id: String) -> InterviewQuestion {
    InterviewQuestion(
        id: id, category: "Swift fundamentals", difficulty: "Junior",
        prompt: "Prompt \(id)", modelAnswer: "Answer", talkingPoints: [], followUps: []
    )
}

struct FlashcardSessionTests {
    @Test func ratingRecordsAndAdvances() {
        let session = FlashcardSession(category: "Swift fundamentals", deck: [makeQuestion("a"), makeQuestion("b")])
        #expect(session.currentCard?.id == "a")
        session.rate(.nailed)
        #expect(session.ratings["a"] == .nailed)
        #expect(session.currentCard?.id == "b")
        #expect(session.isComplete == false)
    }

    @Test func skipAdvancesWithoutRecording() {
        let session = FlashcardSession(category: "Swift fundamentals", deck: [makeQuestion("a"), makeQuestion("b")])
        session.skip()
        #expect(session.ratings["a"] == nil)
        #expect(session.currentCard?.id == "b")
    }

    @Test func isCompleteAfterLastCard() {
        let session = FlashcardSession(category: "Swift fundamentals", deck: [makeQuestion("a")])
        #expect(session.isComplete == false)
        session.rate(.shaky)
        #expect(session.isComplete)
        #expect(session.currentCard == nil)
    }

    @Test func flipSetsIsFlippedAndRatingResetsItForTheNextCard() {
        let session = FlashcardSession(category: "Swift fundamentals", deck: [makeQuestion("a"), makeQuestion("b")])
        session.flip()
        #expect(session.isFlipped)
        session.rate(.missed)
        #expect(session.isFlipped == false)
    }

    @Test func cardsToReviewOrdersMissedBeforeShakyInDeckOrder() {
        let session = FlashcardSession(
            category: "Swift fundamentals",
            deck: [makeQuestion("a"), makeQuestion("b"), makeQuestion("c"), makeQuestion("d")]
        )
        session.rate(.nailed)   // a
        session.rate(.shaky)    // b
        session.rate(.missed)   // c
        session.rate(.shaky)    // d
        #expect(session.cardsToReview.map(\.id) == ["c", "b", "d"])
        #expect(session.nailedCount == 1)
        #expect(session.shakyCount == 2)
        #expect(session.missedCount == 1)
    }

    @Test func progressReflectsRatingsInDeckOrder() {
        let session = FlashcardSession(category: "Swift fundamentals", deck: [makeQuestion("a"), makeQuestion("b")])
        session.rate(.nailed)
        #expect(session.progress == [.nailed, nil])
    }
}
