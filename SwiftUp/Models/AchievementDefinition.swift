import Foundation

/// A flat, plain-Codable description of what unlocks an achievement — deliberately not an
/// associated-value enum (this codebase's models stay plain structs/string enums; see
/// `QuestionFormat`). `kind` selects which optional fields apply:
///   - "streak": days
///   - "totalAnswered": count
///   - "perfectDays": count (all-time days with a perfect 5/5)
///   - "topicMastery": topic, minAccuracy, minAnswered
///   - "perfectWeek": (no fields) — 6 of the last 7 calendar days at >=4/5
///   - "perfectMonth": (no fields) — every day so far this calendar month at >=4/5
///   - "onboarded": (no fields) — at least one completed daily quiz
///   - "unbuildable": (no fields) — depends on a subsystem not built yet; always locked
struct AchievementCriterion: Codable {
    let kind: String
    let topic: String?
    let minAccuracy: Int?
    let minAnswered: Int?
    let count: Int?
    let days: Int?
}

/// Static catalog entry — title/detail/reward/unlock-rule never vary per user.
/// Per-user status/progress is computed at runtime by `AchievementEngine` (Task 4), never stored here.
struct AchievementDefinition: Codable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let sealKind: AchievementSealKind
    let xpReward: Int
    let criterion: AchievementCriterion
}
