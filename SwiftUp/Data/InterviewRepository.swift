import Foundation
import FirebaseFirestore

@Observable
final class InterviewRepository {
    private(set) var categories: [InterviewCategoryContent] = []
    private(set) var isLoading = false
    private(set) var bookmarkedIDs: Set<String> = []

    init() {}

    /// Flattened view of every question across every category/level — used by the bank screen's
    /// header counts ("N questions", "Bookmarks · N").
    var questions: [InterviewQuestion] {
        categories.flatMap { $0.junior + $0.mid + $0.senior }
    }

    /// Synchronously loads bundled fallback content — safe for #Preview, never touches Firestore.
    static func preview(bundle: Bundle = .main) -> InterviewRepository {
        let repo = InterviewRepository()
        repo.categories = loadBundledFallback(bundle: bundle)
        return repo
    }

    static func loadBundledFallback(bundle: Bundle = .main) -> [InterviewCategoryContent] {
        decodeJSONResource([InterviewCategoryContent].self, filename: "interview_bank", bundle: bundle) ?? []
    }

    /// Fetches the shared, public interview question bank from `interviewBank` — one document per
    /// category, authored via `scripts/seed_interview_bank.py`. Not gated on `uid`: this content
    /// is the same for every signed-in user. Falls back to the bundled set if the fetch itself
    /// fails (offline) or succeeds with nothing usable (not yet seeded) — same degrade path as
    /// `dailyQuizzes`.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        let decoded: [InterviewCategoryContent]
        do {
            let snapshot = try await Firestore.firestore().collection("interviewBank")
                .order(by: "order")
                .getDocuments()
            decoded = snapshot.documents.compactMap { try? $0.data(as: InterviewCategoryContent.self) }
        } catch {
            decoded = []
        }
        categories = Self.resolve(decoded: decoded)
    }

    /// Falls back to bundled content whenever the fetch produced nothing usable — whether because
    /// the request itself failed, or because it succeeded against an empty/not-yet-seeded
    /// collection (Firestore's `getDocuments()` does not throw in that case, so "decoded is empty"
    /// has to be treated as a fallback trigger in its own right, not just the `catch` path).
    static func resolve(decoded: [InterviewCategoryContent], bundle: Bundle = .main) -> [InterviewCategoryContent] {
        decoded.isEmpty ? loadBundledFallback(bundle: bundle) : decoded
    }

    /// The first question at `level` in `categoryName`. `nil` if the category doesn't exist, or
    /// has no questions at that level (or at all, for "All").
    func firstQuestion(in categoryName: String, level: String) -> InterviewQuestion? {
        categories.first { $0.name == categoryName }?.questions(for: level).first
    }

    /// First `deckSize` questions at `level` in `categoryName`, in that level's existing content
    /// order (no shuffling — a session deck is stable and deterministic). Fewer than `deckSize` if
    /// the category has less. A category+level combo with zero questions can't be navigated into in
    /// the first place (`InterviewBankView`'s disabled-row handling), so this returning `[]` is
    /// only reachable for a bad `categoryName`.
    func sessionDeck(in categoryName: String, level: String, deckSize: Int = 10) -> [InterviewQuestion] {
        guard let category = categories.first(where: { $0.name == categoryName }) else { return [] }
        return Array(category.questions(for: level).prefix(deckSize))
    }

    /// Walks forward within `current`'s own category and level — the level is inferred from
    /// `current.difficulty`, so no separate level parameter is needed; every question already
    /// carries its own level. Wraps to the next category (in `categories` order) that has at
    /// least one question at that same level, skipping any category with none. With nowhere left
    /// to go, wraps back to the start of `current`'s own level list — a self-loop when that list
    /// has exactly one question, matching this method's pre-existing end-of-bank behavior.
    func nextQuestion(after current: InterviewQuestion) -> InterviewQuestion? {
        guard let categoryIndex = categories.firstIndex(where: { $0.name == current.category }) else { return nil }
        let sameLevel = categories[categoryIndex].questions(for: current.difficulty)
        if let idx = sameLevel.firstIndex(where: { $0.id == current.id }), idx + 1 < sameLevel.count {
            return sameLevel[idx + 1]
        }
        for offset in (categoryIndex + 1)..<categories.count {
            if let next = categories[offset].questions(for: current.difficulty).first {
                return next
            }
        }
        return sameLevel.first
    }

    /// 1-based position of `question` within its own category+level list, and that list's total
    /// count — what `InterviewQuestionDetailView` shows as "Question X of Y".
    func position(of question: InterviewQuestion) -> (index: Int, total: Int)? {
        guard let category = categories.first(where: { $0.name == question.category }) else { return nil }
        let levelQuestions = category.questions(for: question.difficulty)
        guard let idx = levelQuestions.firstIndex(where: { $0.id == question.id }) else { return nil }
        return (index: idx + 1, total: levelQuestions.count)
    }

    /// Nailed cards come back in 4 days; Missed/Shaky come back tomorrow. Pure and static so it's
    /// directly unit-testable without touching Firestore.
    static func dueDate(for rating: FlashcardRating, from date: Date = Date()) -> String {
        let daysUntilDue = rating == .nailed ? 4 : 1
        let due = Calendar.current.date(byAdding: .day, value: daysUntilDue, to: date) ?? date
        return DailyEdition.todayKey(for: due)
    }

    /// Fetches this user's real per-question state (bookmarks; flashcard review state joins this
    /// method in a later pass). Non-blocking on failure — keeps whatever state is already held
    /// rather than flashing to empty on a transient error, same shape as
    /// `ProfileRepository.load(for:)`.
    func loadUserState(for uid: String) async {
        do {
            let bookmarkDocs = try await Firestore.firestore()
                .collection("users").document(uid).collection("bookmarks").getDocuments()
            bookmarkedIDs = Set(bookmarkDocs.documents.map(\.documentID))
        } catch {
            // Non-blocking — see doc comment above.
        }
    }

    /// Creates or deletes `bookmarks/{questionId}` and updates local state immediately
    /// (optimistic — the star responds instantly, matching the rest of this screen).
    func toggleBookmark(_ question: InterviewQuestion, for uid: String) async {
        let wasBookmarked = bookmarkedIDs.contains(question.id)
        if wasBookmarked { bookmarkedIDs.remove(question.id) } else { bookmarkedIDs.insert(question.id) }
        let ref = Firestore.firestore().collection("users").document(uid).collection("bookmarks").document(question.id)
        do {
            if wasBookmarked {
                try await ref.delete()
            } else {
                try await ref.setData(["bookmarked": true])
            }
        } catch {
            // Revert the optimistic update on failure.
            if wasBookmarked { bookmarkedIDs.insert(question.id) } else { bookmarkedIDs.remove(question.id) }
        }
    }

    func isBookmarked(_ question: InterviewQuestion) -> Bool { bookmarkedIDs.contains(question.id) }
}
