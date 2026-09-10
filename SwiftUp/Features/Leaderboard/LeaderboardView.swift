import SwiftUI

struct LeaderboardView: View {
    @Environment(LeaderboardRepository.self) private var repo
    @Environment(AuthRepository.self) private var authRepo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: "All-time", right: "Ranked by total xp")

                Text("Standings").font(Theme.Fonts.heading(32)).padding(.top, 22)

                VStack(spacing: 0) {
                    ForEach(repo.topEntries) { entry in
                        entryRow(entry, isCurrentUser: entry.uid == authRepo.currentUser?.uid)
                    }
                    if let myEntry = repo.myEntry, !repo.topEntries.contains(where: { $0.uid == myEntry.uid }) {
                        entryRow(myEntry, isCurrentUser: true)
                    }
                }
                .padding(.top, 24)

                if repo.myEntry == nil && !repo.isLoading {
                    Text("Finish today's five to join the leaderboard.")
                        .font(Theme.Fonts.body(13)).foregroundStyle(Theme.Colors.neutral800)
                        .padding(.top, 18)
                }

                Text("Scored on total xp earned — every correct answer, plus a 25 xp bonus for a perfect five.")
                    .font(Theme.Fonts.body(13)).foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 18)

                if let myEntry = repo.myEntry, let myPercentile = repo.myPercentile {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            EyebrowLabel("Rank #\(myEntry.rank)")
                            Text("out of \(repo.totalRanked) ranked").font(.system(size: 13)).foregroundStyle(Theme.Colors.neutral800)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            EyebrowLabel("Top \(myPercentile)%")
                            Text("globally").font(.system(size: 13)).foregroundStyle(Theme.Colors.neutral800)
                        }
                    }
                    .padding(.top, 22)
                    .padding(.top, 14)
                    .overlay(Rectangle().fill(Theme.Colors.text).frame(height: 1), alignment: .top)
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
        .task {
            guard let uid = authRepo.currentUser?.uid else { return }
            await repo.load(for: uid)
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: LeaderboardEntry, isCurrentUser: Bool) -> some View {
        let level = LevelCalculator.level(for: entry.totalXP, ladder: repo.levels)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(entry.rank)")
                .font(Theme.Fonts.heading(isCurrentUser ? 17 : 15))
                .foregroundStyle(isCurrentUser ? Theme.Colors.accent700 : Theme.Colors.text)
                .frame(width: 26, alignment: .leading)
            Text(entry.displayName)
                .font(isCurrentUser ? Theme.Fonts.heading(16) : Theme.Fonts.body(15))
            Spacer()
            EyebrowLabel("L\(level.number)", color: isCurrentUser ? Theme.Colors.accent700 : Theme.Colors.neutral700)
            Text("\(entry.totalXP)")
                .font(Theme.Fonts.heading(isCurrentUser ? 18 : 15))
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, isCurrentUser ? 14 : 11)
        .padding(.horizontal, isCurrentUser ? 10 : 0)
        .background(isCurrentUser ? Theme.Colors.accent100 : Color.clear)
        .overlay(alignment: .leading) {
            if isCurrentUser {
                Rectangle().fill(Theme.Colors.accent).frame(width: 3)
            }
        }
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
    }
}

#Preview {
    NavigationStack { LeaderboardView() }
        .environment(LeaderboardRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
