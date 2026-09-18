import Foundation

struct PathSlide: Codable, Identifiable, Hashable {
    let id: String
    let order: Int
    let title: String
    let body: String
    let example: String?
}

struct PathQuizQuestion: Codable, Identifiable, Hashable {
    let id: String
    let prompt: String
    let options: [QuestionOption]
    let correctOptionID: String
}

struct PathStageContent: Codable, Hashable {
    let stageID: String
    let slides: [PathSlide]
    let quiz: [PathQuizQuestion]
}

struct PathRegradeQuiz: Codable, Hashable {
    let grade: SkillLevel
    let questions: [PathQuizQuestion]
}

/// Decodes the single bundled `path_content.json` resource, which holds every stage's content
/// plus every grade's regrade quiz in one file (mirroring how `path_tracks.json` holds every
/// track in one file).
struct PathContentBundle: Codable {
    let stageContent: [PathStageContent]
    let regradeQuizzes: [PathRegradeQuiz]
}
