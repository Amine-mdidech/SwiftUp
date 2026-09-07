import Foundation

@Observable
final class InterviewRepository {
    let categories: [InterviewCategory]
    let questions: [InterviewQuestion]

    init(bundle: Bundle = .main) {
        categories = decodeJSONResource([InterviewCategory].self, filename: "interview_categories", bundle: bundle) ?? []
        questions = decodeJSONResource([InterviewQuestion].self, filename: "interview_questions", bundle: bundle) ?? []
    }

    func firstQuestion(in category: String) -> InterviewQuestion? {
        questions.filter { $0.category == category }.sorted { $0.indexInCategory < $1.indexInCategory }.first
    }

    func nextQuestion(after current: InterviewQuestion) -> InterviewQuestion? {
        let sameCategory = questions.filter { $0.category == current.category }
            .sorted { $0.indexInCategory < $1.indexInCategory }
        guard let idx = sameCategory.firstIndex(where: { $0.id == current.id }) else { return nil }
        if idx + 1 < sameCategory.count { return sameCategory[idx + 1] }
        // wrap to the first question of the next category, if any
        guard let categoryIndex = categories.firstIndex(where: { $0.name == current.category }),
              categoryIndex + 1 < categories.count else { return sameCategory.first }
        return firstQuestion(in: categories[categoryIndex + 1].name) ?? sameCategory.first
    }
}
