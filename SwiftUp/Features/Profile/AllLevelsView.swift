import SwiftUI

struct AllLevelsView: View {
    @Environment(ProfileRepository.self) private var repo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Twelve levels").font(Theme.Fonts.heading(30))

                HStack(alignment: .bottom, spacing: 16) {
                    PlateNumeral("\(repo.profile.level)", font: Theme.Fonts.heading(60))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(repo.profile.levelTitle).font(Theme.Fonts.heading(17))
                        ThinProgressBar(fraction: repo.profile.levelProgressFraction, height: 9)
                        Text("\(repo.profile.xp) of \(repo.profile.xpForNextLevel) xp · \(repo.profile.xpToNextLevel) to go")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, 16)
                .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)

                VStack(spacing: 0) {
                    ForEach(repo.levels) { level in
                        levelRow(level)
                    }
                }
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }

    @ViewBuilder
    private func levelRow(_ level: LevelInfo) -> some View {
        let isCurrent = level.number == repo.profile.level
        let isPast = level.number < repo.profile.level

        HStack(spacing: 12) {
            Text(String(format: "%02d", level.number))
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular, design: .monospaced))
                .frame(width: 22, alignment: .leading)
                .foregroundStyle(isCurrent ? Theme.Colors.accent700 : Theme.Colors.neutral700)
            Text(level.title)
                .font(isCurrent ? Theme.Fonts.heading(15.5) : Theme.Fonts.body(14))
            Spacer()
            if isCurrent {
                EyebrowLabel("You are here", color: Theme.Colors.accent700)
            } else {
                Text("\(level.xpThreshold)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(isPast ? Theme.Colors.neutral700 : Theme.Colors.accent700)
            }
        }
        .padding(.vertical, isCurrent ? 13 : 6)
        .padding(.horizontal, isCurrent ? 10 : 0)
        .background(isCurrent ? Theme.Colors.accent100 : Color.clear)
        .opacity(isPast ? 0.5 : 1)
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)
    }
}

#Preview {
    NavigationStack { AllLevelsView() }
        .environment(ProfileRepository())
}
