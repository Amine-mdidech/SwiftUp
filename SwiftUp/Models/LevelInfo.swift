import Foundation

struct LevelInfo: Codable, Identifiable {
    var id: Int { number }
    let number: Int
    let title: String
    let xpThreshold: Int
}
