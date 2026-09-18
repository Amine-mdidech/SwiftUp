import Foundation

struct UserProfile: Codable {
    let name: String
    let initials: String
    let level: Int
    let levelTitle: String
    let xp: Int
    /// Spendable XP balance — separate from `xp` (lifetime earned, drives the Level ladder above
    /// and must never decrease). This is what Path spending debits; every earn event credits both
    /// by the same amount. See `ProfileRepository.recordCompletion` for the backfill-on-first-touch
    /// rule for users who don't have this field yet.
    let xpBalance: Int
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
