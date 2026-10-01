import Foundation

struct LibrarySlide: Codable, Identifiable, Hashable {
    let id: String
    let order: Int
    let title: String
    let body: String
    let example: String?
}

struct LibraryQuizQuestion: Codable, Identifiable, Hashable {
    let id: String
    let prompt: String
    let options: [QuestionOption]
    let correctOptionID: String
    let explanation: String
}

struct LibraryClassContent: Codable, Hashable {
    let classID: String
    let slides: [LibrarySlide]
    let quiz: [LibraryQuizQuestion]

    private enum CodingKeys: String, CodingKey {
        case classID = "stageID"
        case slides, quiz
    }
}

struct RegradeQuiz: Codable, Hashable {
    let grade: SkillLevel
    let questions: [LibraryQuizQuestion]
}

/// Decodes the single bundled `path_content.json` resource, which holds every class's content
/// plus every grade's regrade quiz in one file (mirroring how `path_tracks.json` holds every path
/// in one file).
struct LibraryContentBundle: Codable {
    let classContent: [LibraryClassContent]
    let regradeQuizzes: [RegradeQuiz]

    private enum CodingKeys: String, CodingKey {
        case classContent = "stageContent"
        case regradeQuizzes
    }
}
