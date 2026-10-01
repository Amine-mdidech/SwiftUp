import SwiftUI

struct MilestonesView: View {
    @Environment(ProfileRepository.self) private var repo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Milestones").font(Theme.Fonts.heading(30))
                Text("\(repo.earnedAchievements.count) printed, \(repo.lockedAchievements.count) to go. \(repo.inReachAchievements.count) are within reach this week.")
                    .font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 10)

                EyebrowLabel("In reach", color: Theme.Colors.accent700).padding(.top, 24)
                VStack(spacing: 16) {
                    ForEach(repo.inReachAchievements) { a in
                        HStack(alignment: .top, spacing: 14) {
                            AchievementSeal(kind: a.sealKind, filled: false, size: 42)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(a.title).font(Theme.Fonts.heading(17))
                                    Spacer()
                                    if let current = a.progressCurrent, let target = a.progressTarget {
                                        EyebrowLabel("\(target - current) to go", color: Theme.Colors.accent700)
                                    }
                                }
                                ThinProgressBar(fraction: a.progressFraction ?? 0, height: 8)
                                Text(a.detail).font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral600)
                            }
                        }
                    }
                }
                .padding(.top, 14)

                EyebrowLabel("Recently printed").padding(.top, 28)
                VStack(spacing: 0) {
                    ForEach(repo.earnedAchievements.prefix(3)) { a in
                        RuledRow {
                            AchievementSeal(kind: a.sealKind, filled: true, size: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.title).font(Theme.Fonts.heading(15.5))
                                Text("+\(a.xpReward) xp").font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral600)
                            }
                            Spacer()
                            EyebrowLabel(a.earnedDateDisplay ?? "")
                        }
                    }
                }
                .padding(.top, 12)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview {
    NavigationStack { MilestonesView() }
        .environment(ProfileRepository.preview())
}
