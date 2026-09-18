import SwiftUI

/// Root screen of the Path tab. Shows the wheel for the user's current grade
/// (`pathRepo.grade`) — not a grade picker; there's no way to view an earlier or later grade's
/// wheel. When the user is Distinguished with every track closed, renders the "nothing left to
/// unlock" terminal state instead (source design turn 15a) rather than an empty wheel.
struct PathWheelView: View {
    @Environment(PathRepository.self) private var pathRepo
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(AuthRepository.self) private var authRepo
    let onEarnXP: () -> Void

    var body: some View {
        Group {
            if pathRepo.isLoading && pathRepo.tracks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.bg)
            } else if isAtTopGrade {
                topGradeContent
            } else {
                wheelContent
            }
        }
        .background(Theme.Colors.bg)
        .task {
            guard let uid = authRepo.currentUser?.uid else { return }
            await pathRepo.load(for: uid)
        }
    }

    private var currentGradeTracks: [PathTrack] { pathRepo.tracks(for: pathRepo.grade) }
    private var closedCount: Int { currentGradeTracks.filter(pathRepo.isTrackClosed).count }
    private var isAtTopGrade: Bool {
        pathRepo.grade == .distinguished && !currentGradeTracks.isEmpty && currentGradeTracks.allSatisfy(pathRepo.isTrackClosed)
    }

    private var wheelContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        EyebrowLabel("\(pathRepo.grade.rawValue) · \(closedCount) of \(currentGradeTracks.count) tracks cleared")
                        Text("The path to \(pathRepo.grade.next?.rawValue ?? "—")").font(Theme.Fonts.heading(22))
                    }
                    Spacer()
                    xpBalanceChip
                }
                .frame(minHeight: 44)

                PathWheelDiagram(
                    tracks: currentGradeTracks, grade: pathRepo.grade, pathRepo: pathRepo,
                    onSelectTrack: { selectedTrack = $0 }
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

                VStack(spacing: 0) {
                    ForEach(currentGradeTracks) { track in
                        trackRow(track)
                    }
                }
                .padding(.top, 14)

                HStack(spacing: 18) {
                    Button("Earn xp →", action: onEarnXP)
                        .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.accent700)
                    NavigationLink("All four grades →") { FourGradesView() }
                        .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.accent700)
                }
                .padding(.top, 16)
                .padding(.top, 13)
                .overlay(Rectangle().fill(Theme.Colors.text).frame(height: 1), alignment: .top)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .navigationDestination(item: $selectedTrack) { track in
            TrackLadderView(track: track)
        }
    }

    @State private var selectedTrack: PathTrack?

    private var xpBalanceChip: some View {
        HStack(spacing: 7) {
            Circle().fill(Theme.Colors.processYellow).frame(width: 10, height: 10)
            Text("\(profileRepo.profile.xpBalance)").font(Theme.Fonts.heading(15)).foregroundStyle(Theme.Colors.accent700)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Theme.Colors.accent100)
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.Colors.accent, lineWidth: 1.5))
    }

    @ViewBuilder
    private func trackRow(_ track: PathTrack) -> some View {
        let closed = pathRepo.isTrackClosed(track)
        let reachable = pathRepo.isTrackReachable(track)
        let row = HStack(spacing: 11) {
            Circle()
                .fill(closed ? Theme.Colors.text : (reachable ? Theme.Colors.accent100 : Theme.Colors.neutral200))
                .overlay(Circle().strokeBorder(reachable && !closed ? Theme.Colors.accent : Color.clear, lineWidth: 2))
                .frame(width: 13, height: 13)
            Text(String(format: "%02d", track.order))
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Colors.neutral700)
                .frame(width: 18, alignment: .leading)
            Text(track.title)
                .font(reachable && !closed ? Theme.Fonts.heading(14.5) : Theme.Fonts.body(14))
                .foregroundStyle(closed || (!reachable) ? Theme.Colors.neutral700 : Theme.Colors.text)
            Spacer()
            Text(trackTrailingLabel(track, closed: closed, reachable: reachable))
                .font(.system(size: 11.5))
                .foregroundStyle(reachable && !closed ? Theme.Colors.accent700 : Theme.Colors.neutral700)
        }
        .frame(minHeight: 44)
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)

        if reachable {
            Button(action: { selectedTrack = track }) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private func trackTrailingLabel(_ track: PathTrack, closed: Bool, reachable: Bool) -> String {
        if closed { return "Cleared" }
        let totalXP = track.stages.reduce(0) { $0 + $1.xpCost }
        if reachable {
            let left = track.stages.count - track.stages.filter(pathRepo.isStageCompleted).count
            return "\(left) left · \(totalXP) xp"
        }
        return "\(track.stages.count) · \(totalXP) xp"
    }

    // MARK: - Top-grade terminal state (source design turn 15a)

    private var topGradeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(Theme.Colors.text).frame(height: 3)
                HStack {
                    EyebrowLabel("Distinguished Engineer")
                    Spacer()
                }
                .padding(.vertical, 7)
                Rectangle().fill(Theme.Colors.text).frame(height: 1)

                Text("Nothing left\nto unlock.").font(Theme.Fonts.heading(34)).padding(.top, 22)
                Text("All \(totalTracksEverywhere) tracks are closed and there is no grade above this one. The daily five carries on for as long as you want it to.")
                    .font(Theme.Fonts.body(15))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 14)

                HStack(alignment: .bottom, spacing: 14) {
                    gradeSeal(size: 44, filled: true)
                    gradeSeal(size: 52, filled: true)
                    gradeSeal(size: 60, filled: true)
                    distinguishedSeal(size: 76)
                }
                .padding(.top, 26)

                HStack(alignment: .bottom, spacing: 18) {
                    PlateNumeral("\(totalTracksEverywhere)", font: Theme.Fonts.heading(64))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("tracks closed").font(Theme.Fonts.heading(16))
                        Text("\(profileRepo.profile.xp) xp").font(Theme.Fonts.body(12.5)).foregroundStyle(Theme.Colors.neutral700)
                    }
                    .padding(.bottom, 8)
                }
                .padding(.top, 24)
                .padding(.top, 14)
                .overlay(Rectangle().fill(Theme.Colors.text).frame(height: 1), alignment: .top)

                EyebrowLabel("What carries on").padding(.top, 20)
                VStack(spacing: 0) {
                    Button(action: onEarnXP) {
                        HStack {
                            Text("The daily five, still there").font(Theme.Fonts.body(14.5)).foregroundStyle(Theme.Colors.text)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
                    NavigationLink { InterviewBankView() } label: {
                        HStack {
                            Text("The interview bank, every grade").font(Theme.Fonts.body(14.5)).foregroundStyle(Theme.Colors.text)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)
                }
                .padding(.top, 10)

                Text("Your xp keeps counting, though there is nothing left to spend it on. There was never anything to buy.")
                    .font(Theme.Fonts.body(12.5))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 14)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
    }

    private var totalTracksEverywhere: Int { pathRepo.tracks.count }

    private func gradeSeal(size: CGFloat, filled: Bool) -> some View {
        ZStack {
            Circle().fill(Theme.Colors.text)
            Path { path in
                path.move(to: CGPoint(x: size * 0.326, y: size * 0.511))
                path.addLine(to: CGPoint(x: size * 0.446, y: size * 0.631))
                path.addLine(to: CGPoint(x: size * 0.674, y: size * 0.402))
            }
            .stroke(Theme.Colors.bg, lineWidth: 3)
        }
        .frame(width: size, height: size)
    }

    private func distinguishedSeal(size: CGFloat) -> some View {
        ZStack {
            Circle().strokeBorder(Theme.Colors.accent, lineWidth: 3)
                .frame(width: size, height: size)
            Circle().strokeBorder(Theme.Colors.accent2, lineWidth: 3)
                .frame(width: size * 13 / 23, height: size * 13 / 23)
            Path { path in
                path.move(to: CGPoint(x: size / 2, y: 0))
                path.addLine(to: CGPoint(x: size / 2, y: size))
                path.move(to: CGPoint(x: 0, y: size / 2))
                path.addLine(to: CGPoint(x: size, y: size / 2))
            }
            .stroke(Theme.Colors.text, lineWidth: 1.2)
            Circle().fill(Theme.Colors.processYellow)
                .frame(width: size * 5 / 23, height: size * 5 / 23)
        }
        .frame(width: size, height: size)
    }
}

#Preview("Mid-grade") {
    NavigationStack {
        PathWheelView(onEarnXP: {})
    }
    .environment(PathRepository.preview())
    .environment(ProfileRepository.preview())
    .environment(AuthRepository(isPreview: true, signedIn: true))
}
