import Foundation

struct LeaderboardEntry: Codable, Identifiable {
    var id: String { name }
    let rank: Int
    let name: String
    let level: Int
    let xp: Int
    let isCurrentUser: Bool
}
