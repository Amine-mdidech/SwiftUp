import Foundation

enum QuestionSelector {
    /// True once every question in the bank has been answered — the trigger for skill-level promotion.
    static func shouldPromote(bank: [Question], answered: [String: Date]) -> Bool {
        guard !bank.isEmpty else { return false }
        return bank.allSatisfy { answered[$0.id] != nil }
    }
}
