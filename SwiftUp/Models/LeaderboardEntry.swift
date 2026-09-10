import Foundation

struct LeaderboardEntry: Identifiable {
    let uid: String
    var id: String { uid }
    let displayName: String
    let totalXP: Int
    let rank: Int
}
