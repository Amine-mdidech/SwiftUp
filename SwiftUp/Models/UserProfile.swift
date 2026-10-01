import Foundation

struct UserProfile: Codable {
    let name: String
    let initials: String
    let xp: Int
    /// Spendable XP balance — separate from `xp` (lifetime earned, must never decrease). This is
    /// what Path spending debits; every earn event credits both by the same amount. See
    /// `ProfileRepository.recordCompletion` for the backfill-on-first-touch rule for users who
    /// don't have this field yet.
    let xpBalance: Int
    let streakDays: Int
    let freezesAvailable: Int
    let freezesTotal: Int
    let answeredCount: Int
    let accuracyPercent: Int
    let memberSinceDisplay: String
}
