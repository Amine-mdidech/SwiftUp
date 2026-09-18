import Foundation

/// Shape of a `dailyQuizzes/{date}` Firestore document: one shared quiz per calendar day, with a
/// distinct 5-question set per skill level. The edition number and the exact questions are
/// authored server-side (see `scripts/seed_daily_quizzes.py`) — every user at a given level sees
/// the same edition, same questions, same day.
struct DailyQuizDocument: Codable {
    let edition: Int
    let junior: [Question]
    let mid: [Question]
    let senior: [Question]

    func questions(for level: SkillLevel) -> [Question] {
        switch level {
        case .junior: junior
        case .mid: mid
        case .senior, .distinguished: senior
        }
    }
}
