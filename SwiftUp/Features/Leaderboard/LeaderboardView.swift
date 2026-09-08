import SwiftUI

struct LeaderboardView: View {
    @Environment(LeaderboardRepository.self) private var repo
    @State private var board = "Friends"
    @State private var span = "Week"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: "Week 36", right: "Closes Sunday 24:00")

                Text("Standings").font(Theme.Fonts.heading(32)).padding(.top, 22)

                HStack(spacing: 10) {
                    SegmentedPicker(options: ["Friends", "Global"], selection: $board)
                    SegmentedPicker(options: ["Week", "All time"], selection: $span)
                }
                .padding(.top, 16)

                VStack(spacing: 0) {
                    ForEach(repo.entries) { entry in
                        entryRow(entry)
                    }
                }
                .padding(.top, 24)

                Text("Scored on xp earned this week only — 15 per correct answer, 25 for a perfect five, nothing for streak length.")
                    .font(Theme.Fonts.body(13)).foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 18)

                if let currentUser = repo.entries.first(where: \.isCurrentUser),
                   let secondPlace = repo.entries.first(where: { $0.rank == currentUser.rank - 1 }) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            EyebrowLabel("\(secondPlace.xp - currentUser.xp) xp")
                            Text("behind second place").font(.system(size: 13)).foregroundStyle(Theme.Colors.neutral800)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            EyebrowLabel("Top 4%")
                            Text("globally this week").font(.system(size: 13)).foregroundStyle(Theme.Colors.neutral800)
                        }
                    }
                    .padding(.top, 22)
                    .padding(.top, 14)
                    .overlay(Rectangle().fill(Theme.Colors.text).frame(height: 1), alignment: .top)
                }

                Text("Listed because leaderboards are on in settings. Turn them off and you disappear from everyone else's board too.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 16)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }

    @ViewBuilder
    private func entryRow(_ entry: LeaderboardEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(entry.rank)")
                .font(Theme.Fonts.heading(entry.isCurrentUser ? 17 : 15))
                .foregroundStyle(entry.isCurrentUser ? Theme.Colors.accent700 : Theme.Colors.text)
                .frame(width: 26, alignment: .leading)
            Text(entry.name)
                .font(entry.isCurrentUser ? Theme.Fonts.heading(16) : Theme.Fonts.body(15))
            Spacer()
            EyebrowLabel("L\(entry.level)", color: entry.isCurrentUser ? Theme.Colors.accent700 : Theme.Colors.neutral700)
            Text("\(entry.xp)")
                .font(Theme.Fonts.heading(entry.isCurrentUser ? 18 : 15))
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, entry.isCurrentUser ? 14 : 11)
        .padding(.horizontal, entry.isCurrentUser ? 10 : 0)
        .background(entry.isCurrentUser ? Theme.Colors.accent100 : Color.clear)
        .overlay(alignment: .leading) {
            if entry.isCurrentUser {
                Rectangle().fill(Theme.Colors.accent).frame(width: 3)
            }
        }
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
    }
}

#Preview {
    NavigationStack { LeaderboardView() }
        .environment(LeaderboardRepository())
}
