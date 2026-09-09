import Foundation

enum SkillLevel: String, CaseIterable, Identifiable, Codable {
    case junior = "Junior", mid = "Mid", senior = "Senior"
    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .junior: "Shipping with SwiftUI, still meeting the SDK. Under two years."
        case .mid: "Comfortable in UIKit and SwiftUI, reaching for concurrency and architecture. Two to five years."
        case .senior: "Leading work, designing systems, interviewing others. Five years and up."
        }
    }

    /// The next level to promote to when this level's question bank is exhausted. `nil` at the ceiling (senior).
    var next: SkillLevel? {
        switch self {
        case .junior: .mid
        case .mid: .senior
        case .senior: nil
        }
    }
}
