import Foundation

struct TopicAccuracy: Codable, Identifiable {
    var id: String { name }
    let name: String
    let accuracyPercent: Int
}
