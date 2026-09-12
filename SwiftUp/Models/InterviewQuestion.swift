import Foundation

struct InterviewQuestion: Codable, Identifiable {
    let id: String
    let category: String
    let difficulty: String
    let prompt: String
    let modelAnswer: String
    let talkingPoints: [String]
    let followUps: [String]
}
