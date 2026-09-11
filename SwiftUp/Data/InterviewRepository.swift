import Foundation
import FirebaseFirestore

@Observable
final class InterviewRepository {
    private(set) var categories: [InterviewCategoryContent] = []
    private(set) var isLoading = false

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
    /// is the same for every signed-in user. Falls back to the bundled set only if the fetch
    /// itself fails (offline, not yet seeded) — same degrade path as `dailyQuizzes`.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await Firestore.firestore().collection("interviewBank").getDocuments()
            categories = snapshot.documents.compactMap { try? $0.data(as: InterviewCategoryContent.self) }
        } catch {
            categories = Self.loadBundledFallback()
        }
    }

    /// The first question at `level` in `categoryName`. `nil` if the category doesn't exist, or
    /// has no questions at that level (or at all, for "All").
    func firstQuestion(in categoryName: String, level: String) -> InterviewQuestion? {
        categories.first { $0.name == categoryName }?.questions(for: level).first
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
}
