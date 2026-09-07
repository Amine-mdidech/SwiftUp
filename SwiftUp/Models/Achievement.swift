import Foundation
import SwiftUI

enum AchievementStatus: String, Codable {
    case earned, inReach, locked
}

struct Achievement: Codable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let sealKind: AchievementSealKind
    let status: AchievementStatus
    let xpReward: Int
    let earnedDateDisplay: String?
    let progressCurrent: Int?
    let progressTarget: Int?

    var progressFraction: Double? {
        guard let current = progressCurrent, let target = progressTarget, target > 0 else { return nil }
        return max(0, min(1, Double(current) / Double(target)))
    }
}
