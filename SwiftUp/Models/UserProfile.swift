import Foundation

struct UserProfile: Codable {
    let name: String
    let initials: String
    let level: Int
    let levelTitle: String
    let xp: Int
    let xpForCurrentLevel: Int
    let xpForNextLevel: Int
    let streakDays: Int
    let freezesAvailable: Int
    let freezesTotal: Int
    let answeredCount: Int
    let accuracyPercent: Int
    let memberSinceDisplay: String

    var xpToNextLevel: Int { max(0, xpForNextLevel - xp) }

    var levelProgressFraction: Double {
        let span = Double(xpForNextLevel - xpForCurrentLevel)
        guard span > 0 else { return 0 }
        return max(0, min(1, Double(xp - xpForCurrentLevel) / span))
    }
}
