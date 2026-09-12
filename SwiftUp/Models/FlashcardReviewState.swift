import Foundation

enum FlashcardRating: String, Codable {
    case missed, shaky, nailed
}

/// One user's stored review state for one interview-prep question, decoded from
/// `users/{uid}/flashcardReviews/{questionId}`. `lastReviewedAt` is written but never read back
/// into the app, so it's omitted from this decode target.
struct FlashcardReviewState: Codable {
    let rating: FlashcardRating
    let dueDate: String
    let reviewCount: Int
}
