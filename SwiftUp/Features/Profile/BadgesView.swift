import SwiftUI

struct BadgesView: View {
    @Environment(ProfileRepository.self) private var repo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Badges").font(Theme.Fonts.heading(30))
                HStack(spacing: 8) {
                    PlateNumeral("\(repo.earnedAchievements.count)", font: Theme.Fonts.heading(32))
                    Text("of \(repo.achievements.count) earned").font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral700)
                }
                .padding(.top, 10)

                EyebrowLabel("Earned").padding(.top, 26)
                VStack(spacing: 0) {
                    ForEach(Array(repo.earnedAchievements.prefix(4).enumerated()), id: \.element.id) { index, a in
                        RuledRow(minHeight: 50) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.accent700)
                                .frame(width: 26, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.title).font(Theme.Fonts.heading(15.5))
                                Text(a.detail).font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral600)
                            }
                            Spacer()
                            EyebrowLabel(a.earnedDateDisplay ?? "")
                        }
                    }
                }
                .padding(.top, 10)

                if repo.earnedAchievements.count > 4 {
                    Text("\(repo.earnedAchievements.count - 4) more earned →")
                        .font(.system(size: 13)).foregroundStyle(Theme.Colors.accent700)
                        .padding(.top, 10)
                }

                EyebrowLabel("Next up").padding(.top, 24)
                VStack(spacing: 0) {
                    ForEach(Array((repo.inReachAchievements).enumerated()), id: \.element.id) { index, a in
                        RuledRow(minHeight: 50) {
                            Text(String(format: "%02d", 10 + index))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.neutral600)
                                .frame(width: 26, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.title).font(Theme.Fonts.heading(15.5))
                                Text(a.detail).font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral600)
                            }
                            Spacer()
                        }
                        .opacity(0.55)
                    }
                }
                .padding(.top, 10)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview {
    NavigationStack { BadgesView() }
        .environment(ProfileRepository.preview())
}
