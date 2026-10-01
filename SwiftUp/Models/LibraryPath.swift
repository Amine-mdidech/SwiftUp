import Foundation

struct LibraryClass: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case lesson, assessment }
    let id: String
    let order: Int
    let title: String
    /// XP awarded the first time this class's quiz is passed — a replay (e.g. going for a perfect
    /// score after already passing) never re-awards it. Decodes from the JSON/Firestore key
    /// `xpCost`, unchanged from when classes cost XP to start rather than earning it on completion
    /// — renaming the wire field would mean migrating already-seeded content for no behavioral
    /// benefit.
    let xpReward: Int
    let kind: Kind

    private enum CodingKeys: String, CodingKey {
        case id, order, title, kind
        case xpReward = "xpCost"
    }
}

struct LibraryPath: Codable, Identifiable, Hashable {
    let id: String
    let grade: SkillLevel
    let order: Int
    let title: String
    /// One-line summary shown under the path's title on its detail screen (e.g. "Running work at
    /// the same time without data races." for Concurrency).
    let summary: String
    let classes: [LibraryClass]

    private enum CodingKeys: String, CodingKey {
        case id, grade, order, title, summary
        case classes = "stages"
    }

    /// Sorts `classes` by `.order` regardless of the array's order in the source — every consumer
    /// (`LibraryRepository.isPathSealed`/`canStartClass`, `LibraryPathView`'s class list and
    /// progress segments) assumes `classes` is already in play order rather than re-sorting itself,
    /// so this is the one place that guarantee needs to hold, for both this initializer and the
    /// decoded path below.
    init(id: String, grade: SkillLevel, order: Int, title: String, summary: String, classes: [LibraryClass]) {
        self.id = id
        self.grade = grade
        self.order = order
        self.title = title
        self.summary = summary
        self.classes = classes.sorted { $0.order < $1.order }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        grade = try container.decode(SkillLevel.self, forKey: .grade)
        order = try container.decode(Int.self, forKey: .order)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        classes = try container.decode([LibraryClass].self, forKey: .classes).sorted { $0.order < $1.order }
    }
}
