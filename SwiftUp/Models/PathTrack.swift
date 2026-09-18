import Foundation

struct PathStage: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case lesson, assessment }
    let id: String
    let order: Int
    let title: String
    let xpCost: Int
    let kind: Kind
}

struct PathTrack: Codable, Identifiable, Hashable {
    let id: String
    let grade: SkillLevel
    let order: Int
    let title: String
    let stages: [PathStage]
}
