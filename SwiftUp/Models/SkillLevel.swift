import Foundation

/// `CaseIterable`'s `allCases` includes `.distinguished` — for any UI offering a level to pick
/// from (not just display it), use `onboardingChoices` instead, which deliberately excludes it.
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

    /// User-facing name — differs from `rawValue` only for `.mid` ("Intermediate" reads better
    /// than "Mid" in the grade switcher, ladder, and Settings). `rawValue` stays "Mid" everywhere
    /// it's persisted (Firestore field values, `pathRegradeQuizzes` doc IDs) so this is purely a
    /// display concern.
    var displayName: String {
        switch self {
        case .mid: "Intermediate"
        default: rawValue
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

    /// The Library's "volume" numeral (I/II/III/IV) — purely a presentation label for grouping
    /// paths by grade there; carries no other meaning.
    var volumeNumeral: String {
        switch self {
        case .junior: "I"
        case .mid: "II"
        case .senior: "III"
        case .distinguished: "IV"
        }
    }

    /// A one-line theme summarizing the volume's paths, e.g. "Volume II · Concurrency & data".
    var volumeSubtitle: String {
        switch self {
        case .junior: "Foundations"
        case .mid: "Concurrency & data"
        case .senior: "Systems & leadership"
        case .distinguished: "Platform & direction"
        }
    }
}
