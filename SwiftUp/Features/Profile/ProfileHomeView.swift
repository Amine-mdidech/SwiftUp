import SwiftUI

struct ProfileHomeView: View {
    @Environment(ProfileRepository.self) private var repo
    @Environment(LibraryRepository.self) private var libraryRepo
    @Environment(AuthRepository.self) private var authRepo

    var body: some View {
        Group {
            if repo.isLoading && repo.profile.name.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.bg)
            } else {
                profileContent
            }
        }
        .background(Theme.Colors.bg)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Settings") { SettingsView() }
            }
        }
        .task {
            guard let uid = authRepo.currentUser?.uid else { return }
            await libraryRepo.load(for: uid)
        }
    }

    private var mastheadRank: String { libraryRepo.grade.displayName }

    private var profileContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: repo.profile.name, right: mastheadRank)

                HStack(alignment: .top, spacing: 16) {
                    Circle().fill(Theme.Colors.neutral200)
                        .frame(width: 58, height: 58)
                        .overlay(Text(repo.profile.initials).font(Theme.Fonts.heading(22)).foregroundStyle(Theme.Colors.neutral700))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(repo.profile.name).font(Theme.Fonts.heading(28))
                        Text("\(repo.profile.xp) xp")
                            .font(Theme.Fonts.body(14.5)).foregroundStyle(Theme.Colors.neutral700)
                    }
                }
                .padding(.top, 24)

                HStack {
                    EyebrowLabel("Grade: \(libraryRepo.grade.displayName)")
                    Spacer()
                    NavigationLink("All four grades →") { FourGradesView() }
                        .font(.system(size: 12)).foregroundStyle(Theme.Colors.accent700)
                }
                .padding(.top, 10)

                HStack(spacing: 24) {
                    statBlock("Streak") { PlateNumeral("\(repo.profile.streakDays)", font: Theme.Fonts.heading(52)) }
                    statBlock("Answered") { Text("\(repo.profile.answeredCount)").font(Theme.Fonts.heading(52)) }
                    statBlock("Accuracy") { Text("\(repo.profile.accuracyPercent)%").font(Theme.Fonts.heading(52)) }
                }
                .padding(.top, 26)

                HStack {
                    EyebrowLabel("Weakest topics")
                    Spacer()
                    NavigationLink("All topics →") { AccuracyByTopicView() }
                        .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.accent700)
                }
                .padding(.top, 28)

                VStack(spacing: 10) {
                    ForEach(repo.topics.sorted { $0.accuracyPercent < $1.accuracyPercent }.prefix(2)) { topic in
                        HStack(spacing: 12) {
                            Text(topic.name).font(Theme.Fonts.body(13.5)).frame(width: 106, alignment: .leading)
                            ThinProgressBar(fraction: Double(topic.accuracyPercent) / 100, fillColor: Theme.Colors.accent2, height: 7)
                            Text("\(topic.accuracyPercent)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.Colors.neutral600)
                        }
                    }
                }
                .padding(.top, 12)

                HStack {
                    EyebrowLabel("Seals earned")
                    Spacer()
                    NavigationLink("\(repo.earnedAchievements.count) / \(repo.achievements.count)") { BadgesView() }
                        .font(.system(size: 11)).foregroundStyle(Theme.Colors.neutral700)
                }
                .padding(.top, 26)

                HStack(spacing: 14) {
                    ForEach(repo.earnedAchievements.prefix(4)) { a in
                        AchievementSeal(kind: a.sealKind, filled: true, size: 46)
                    }
                    LockedSeal(remainingCount: repo.lockedAchievements.count, size: 46)
                }
                .padding(.top, 14)

                HStack {
                    EyebrowLabel("Next milestone")
                    Spacer()
                    NavigationLink("All milestones →") { MilestonesView() }
                        .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.accent700)
                }
                .padding(.top, 28)

                VStack(spacing: 14) {
                    ForEach(repo.inReachAchievements.prefix(2)) { a in
                        milestoneRow(a)
                    }
                }
                .padding(.top, 12)

                HStack {
                    EyebrowLabel("Sixteen weeks")
                    Spacer()
                    EyebrowLabel("Freezes \(repo.profile.freezesAvailable) of \(repo.profile.freezesTotal)")
                }
                .padding(.top, 28)

                StreakCalendarGrid(days: repo.streakCalendarDays)
                    .padding(.top, 12)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func statBlock<Content: View>(_ label: String, @ViewBuilder value: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            EyebrowLabel(label)
            value()
        }
    }

    @ViewBuilder
    private func milestoneRow(_ achievement: Achievement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text(achievement.title).font(Theme.Fonts.heading(18))
                Spacer()
                if let current = achievement.progressCurrent, let target = achievement.progressTarget {
                    EyebrowLabel("\(target - current) to go", color: Theme.Colors.accent700)
                }
            }
            ThinProgressBar(fraction: achievement.progressFraction ?? 0, fillColor: achievement.sealKind == .topicMastery ? Theme.Colors.accent2 : Theme.Colors.accent, height: 8)
            Text(achievement.detail).font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
        }
        .padding(.top, 12)
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
    }
}

#Preview {
    NavigationStack { ProfileHomeView() }
        .environment(ProfileRepository.preview())
        .environment(LibraryRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
