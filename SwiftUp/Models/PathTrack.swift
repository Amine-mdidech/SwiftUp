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

    private enum CodingKeys: String, CodingKey {
        case id, grade, order, title, stages
    }

    /// Sorts `stages` by `.order` regardless of the array's order in the source — every consumer
    /// (`PathRepository.isTrackClosed`/`isStageUnlocked`, `TrackLadderView`'s ladder/progress
    /// segments) assumes `stages` is already in play order rather than re-sorting itself, so this
    /// is the one place that guarantee needs to hold, for both this initializer and the decoded
    /// path below.
    init(id: String, grade: SkillLevel, order: Int, title: String, stages: [PathStage]) {
        self.id = id
        self.grade = grade
        self.order = order
        self.title = title
        self.stages = stages.sorted { $0.order < $1.order }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        grade = try container.decode(SkillLevel.self, forKey: .grade)
        order = try container.decode(Int.self, forKey: .order)
        title = try container.decode(String.self, forKey: .title)
        stages = try container.decode([PathStage].self, forKey: .stages).sorted { $0.order < $1.order }
    }
}
