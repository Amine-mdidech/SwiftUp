import Foundation

@Observable
final class ProfileRepository {
    let profile: UserProfile
    let levels: [LevelInfo]
    let achievements: [Achievement]
    let topics: [TopicAccuracy]

    init(bundle: Bundle = .main) {
        profile = decodeJSONResource(UserProfile.self, filename: "profile", bundle: bundle)
            ?? UserProfile(name: "", initials: "", level: 0, levelTitle: "", xp: 0, xpForCurrentLevel: 0, xpForNextLevel: 1, streakDays: 0, freezesAvailable: 0, freezesTotal: 0, answeredCount: 0, accuracyPercent: 0, memberSinceDisplay: "")
        levels = decodeJSONResource([LevelInfo].self, filename: "levels", bundle: bundle) ?? []
        achievements = decodeJSONResource([Achievement].self, filename: "achievements", bundle: bundle) ?? []
        topics = decodeJSONResource([TopicAccuracy].self, filename: "topics", bundle: bundle) ?? []
    }

    var earnedAchievements: [Achievement] { achievements.filter { $0.status == .earned } }
    var inReachAchievements: [Achievement] { achievements.filter { $0.status == .inReach } }
    var lockedAchievements: [Achievement] { achievements.filter { $0.status == .locked } }
}
