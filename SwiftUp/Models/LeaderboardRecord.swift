import Foundation

/// A minimal public record — decoded either from a `leaderboardEntries/{uid}` Firestore document
/// (where `uid` is filled in from the document ID, not stored as a field) or from the bundled
/// offline-fallback JSON (`leaderboard.json`, where `uid` is an explicit field since there's no
/// document ID to borrow it from).
struct LeaderboardRecord: Codable {
    let uid: String
    let displayName: String
    let totalXP: Int
}
