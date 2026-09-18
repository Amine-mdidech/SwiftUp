import Foundation

enum SkillLevel: String, CaseIterable, Identifiable, Codable {
    case junior = "Junior", mid = "Mid", senior = "Senior", distinguished = "Distinguished"
    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .junior: "Shipping with SwiftUI, still meeting the SDK. Under two years."
        case .mid: "Comfortable in UIKit and SwiftUI, reaching for concurrency and architecture. Two to five years."
        case .senior: "Leading work, designing systems, interviewing others. Five years and up."
        case .distinguished: "Platform strategy, cross-team architecture, technical direction."
        }
    }

    /// The next grade Path's regrade quiz promotes to (a later sub-project). `nil` at the
    /// ceiling — matches the source design's "no grade above this one."
    var next: SkillLevel? {
        switch self {
        case .junior: .mid
        case .mid: .senior
        case .senior: .distinguished
        case .distinguished: nil
        }
    }

    /// Grades the onboarding assessment offers. Nobody starts at Distinguished — it's only
    /// reachable by climbing every track in every earlier grade.
    static let onboardingChoices: [SkillLevel] = [.junior, .mid, .senior]
}
