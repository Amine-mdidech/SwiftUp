import Foundation

enum QuestionFormat: String, Codable {
    case multipleChoice, trueFalse, spotTheBug, fillInTheBlank
}

struct QuestionOption: Codable, Identifiable, Hashable {
    let id: String
    let text: String
}

struct Question: Codable, Identifiable {
    let id: String
    let topic: String
    let format: QuestionFormat
    let prompt: String
    let codeSnippet: String?
    let options: [QuestionOption]
    let correctOptionID: String
    let explanation: String
    let xp: Int
}
