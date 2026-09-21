import SwiftUI

/// Pushed from `PathWheelView` when a reachable or closed track is tapped. Tapping the spend
/// button unlocks the next stage — a one-time xp cost, see `PathRepository.startStage` — then
/// opens its slides (lesson stages) or quiz (assessment stages) directly.
struct TrackLadderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(PathRepository.self) private var pathRepo
    @Environment(AuthRepository.self) private var authRepo
    let track: PathTrack
    var adPresenter: RewardedAdPresenting = NoOpAdPresenter()

    @State private var activeAttempt: StageAttempt?
    @State private var spendAlert: SpendAlert?
    @State private var adUnlockOffer: PathStage?
    @State private var isSpending = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button("← The wheel") { dismiss() }
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.accent700)
                    Spacer()
                    xpBalanceChip
                }
                .frame(minHeight: 44)

                HStack(alignment: .center, spacing: 14) {
                    Text(String(format: "%02d", track.order))
                        .font(Theme.Fonts.heading(19))
                        .frame(width: 56, height: 56)
                        .background(Theme.Colors.accent100)
                        .foregroundStyle(Theme.Colors.accent700)
                        .overlay(Circle().strokeBorder(Theme.Colors.accent, lineWidth: 3))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        EyebrowLabel("Track \(String(format: "%02d", track.order)) of \(String(format: "%02d", totalTracksInGrade))")
                        Text(track.title).font(Theme.Fonts.heading(22))
                    }
                }
                .padding(.top, 8)

                HStack(spacing: 4) {
                    ForEach(track.stages) { stage in
                        Rectangle()
                            .fill(segmentColor(for: stage))
                            .frame(height: 8)
                    }
                }
                .padding(.top, 16)

                HStack {
                    EyebrowLabel("\(closedStageCount) cleared · \(bankedXP) xp banked")
                    Spacer()
                    EyebrowLabel("\(track.stages.count - closedStageCount) to go", color: Theme.Colors.accent700)
                }
                .padding(.top, 7)

                VStack(spacing: 0) {
                    ForEach(track.stages) { stage in
                        stageRow(stage)
                    }
                }
                .padding(.top, 18)

                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .lastTextBaseline) {
                        Text(remainingSummary)
                            .font(Theme.Fonts.body(13.5))
                            .foregroundStyle(Theme.Colors.neutral800)
                        Spacer()
                        Text("\(remainingXP) xp")
                            .font(Theme.Fonts.heading(15))
                    }
                    ThinProgressBar(fraction: closedFraction, height: 7)
                    HStack {
                        EyebrowLabel("\(remainingXP) to close", color: Theme.Colors.accent700)
                        Spacer()
                        EyebrowLabel("\(profileRepo.profile.xpBalance) held")
                    }
                }
                .padding(.top, 16)
                .padding(.top, 14)
                .overlay(Rectangle().fill(Theme.Colors.text).frame(height: 1), alignment: .top)

                if let nextStage {
                    Button(action: { spend(nextStage) }) {
                        Text(pathRepo.isStageStarted(nextStage)
                            ? "Continue stage \(String(format: "%02d", nextStage.order)) · no further charge"
                            : "Spend \(nextStage.xpCost) xp · start stage \(String(format: "%02d", nextStage.order))")
                            .font(Theme.Fonts.heading(17))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .background(Theme.Colors.accent)
                    .foregroundStyle(Theme.Colors.bg)
                    .opacity(isSpending ? 0.6 : 1)
                    .disabled(isSpending)
                    .padding(.top, 16)
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
        .navigationBarBackButtonHidden()
        .navigationDestination(item: $activeAttempt) { attempt in
            if attempt.stage.kind == .assessment {
                PathQuizView(
                    title: attempt.stage.title,
                    questions: attempt.content.quiz,
                    onPassed: { await pathRepo.completeStage(attempt.stage, for: authRepo.currentUser?.uid ?? "") },
                    onFinished: { activeAttempt = nil },
                    onAbandon: { activeAttempt = nil }
                )
            } else {
                PathStageSlidesView(
                    stage: attempt.stage, content: attempt.content,
                    onPassed: { await pathRepo.completeStage(attempt.stage, for: authRepo.currentUser?.uid ?? "") },
                    onFinished: { activeAttempt = nil },
                    onAbandon: { activeAttempt = nil }
                )
            }
        }
        .alert(item: $spendAlert) { alert in
            Alert(title: Text("Can't start this stage"), message: Text(alert.message))
        }
        .sheet(item: $adUnlockOffer) { stage in
            AdUnlockSheet(
                stage: stage, balance: profileRepo.profile.xpBalance,
                canWatchAd: pathRepo.hasAdUnlockAvailableToday,
                onWatchAd: { watchAdToUnlock(stage) }
            )
        }
    }

    private var xpBalanceChip: some View {
        HStack(spacing: 7) {
            Circle().fill(Theme.Colors.processYellow).frame(width: 10, height: 10)
            Text("\(profileRepo.profile.xpBalance)").font(Theme.Fonts.heading(15)).foregroundStyle(Theme.Colors.accent700)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Theme.Colors.accent100)
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.Colors.accent, lineWidth: 1.5))
    }

    private var totalTracksInGrade: Int { pathRepo.tracks(for: track.grade).count }
    private var closedStageCount: Int { track.stages.filter(pathRepo.isStageCompleted).count }
    private var bankedXP: Int { track.stages.filter(pathRepo.isStageCompleted).reduce(0) { $0 + $1.xpCost } }
    private var remainingXP: Int { track.stages.filter { !pathRepo.isStageCompleted($0) }.reduce(0) { $0 + $1.xpCost } }
    private var closedFraction: Double {
        guard !track.stages.isEmpty else { return 0 }
        return Double(closedStageCount) / Double(track.stages.count)
    }
    private var remainingSummary: String {
        let left = track.stages.count - closedStageCount
        return left == 1 ? "One stage left to close the track" : "\(left) stages left to close the track"
    }
    private var nextStage: PathStage? {
        track.stages.first { !pathRepo.isStageCompleted($0) }
    }

    private func spend(_ stage: PathStage) {
        guard let uid = authRepo.currentUser?.uid else { return }
        isSpending = true
        Task {
            defer { isSpending = false }
            let result = await pathRepo.startStage(stage, cost: stage.xpCost, for: uid)
            switch result {
            case .started(let newBalance):
                profileRepo.applyExternalXPBalance(newBalance)
                await openContent(for: stage)
            case .alreadyStarted:
                await openContent(for: stage)
            case .insufficientXP(let balance):
                profileRepo.applyExternalXPBalance(balance)
                adUnlockOffer = stage
            case .failed:
                spendAlert = .writeFailed
            }
        }
    }

    private func watchAdToUnlock(_ stage: PathStage) {
        guard let uid = authRepo.currentUser?.uid else { return }
        adPresenter.presentAd { completed in
            guard completed else { return }
            Task {
                guard await pathRepo.unlockStageViaAd(stage, for: uid) else { return }
                await openContent(for: stage)
            }
        }
    }

    private func openContent(for stage: PathStage) async {
        guard let content = await pathRepo.fetchStageContent(for: stage) else {
            spendAlert = .contentUnavailable
            return
        }
        activeAttempt = StageAttempt(stage: stage, content: content)
    }

    private func segmentColor(for stage: PathStage) -> Color {
        if pathRepo.isStageCompleted(stage) { return Theme.Colors.text }
        if stage.id == nextStage?.id { return Theme.Colors.accent }
        return Theme.Colors.neutral200
    }

    @ViewBuilder
    private func stageRow(_ stage: PathStage) -> some View {
        let closed = pathRepo.isStageCompleted(stage)
        let isNext = stage.id == nextStage?.id

        HStack(spacing: 13) {
            Group {
                if closed {
                    Text("✓").font(Theme.Fonts.heading(14))
                        .frame(width: 32, height: 32)
                        .background(Theme.Colors.text)
                        .foregroundStyle(Theme.Colors.bg)
                        .clipShape(Circle())
                } else if stage.kind == .assessment {
                    Circle()
                        .strokeBorder(Theme.Colors.neutral400, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                        .frame(width: 32, height: 32)
                        .overlay(Text(String(format: "%02d", stage.order)).font(.system(size: 11, weight: .semibold)))
                } else {
                    Text(String(format: "%02d", stage.order))
                        .font(Theme.Fonts.heading(isNext ? 13 : 12))
                        .frame(width: 32, height: 32)
                        .background(isNext ? Theme.Colors.accent100 : Theme.Colors.bg)
                        .foregroundStyle(isNext ? Theme.Colors.accent700 : Theme.Colors.neutral700)
                        .overlay(Circle().strokeBorder(isNext ? Theme.Colors.accent : Theme.Colors.divider, lineWidth: isNext ? 3 : 1.5))
                        .clipShape(Circle())
                }
            }

            Text(stage.title)
                .font(isNext ? Theme.Fonts.heading(15.5) : Theme.Fonts.body(14))
                .foregroundStyle(closed ? Theme.Colors.neutral700 : Theme.Colors.text)

            Spacer()

            Text(isNext ? "\(stage.xpCost) xp · Next" : "\(stage.xpCost) xp")
                .font(isNext ? Theme.Fonts.heading(12.5) : .system(size: 11.5))
                .foregroundStyle(isNext ? Theme.Colors.accent700 : Theme.Colors.neutral700)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, isNext ? 9 : 0)
        .background(isNext ? Theme.Colors.accent100 : Color.clear)
        .overlay(isNext ? Rectangle().fill(Theme.Colors.accent).frame(width: 3) : nil, alignment: .leading)
    }
}

/// Bundles a stage with the content already fetched for it, so `TrackLadderView`'s single
/// `.navigationDestination(item:)` has everything it needs to route to slides (lesson) or
/// straight to a quiz (assessment) without a second async fetch mid-navigation.
private struct StageAttempt: Identifiable, Hashable {
    let stage: PathStage
    let content: PathStageContent
    var id: String { stage.id }
}

private enum SpendAlert: Identifiable {
    case contentUnavailable
    case writeFailed

    var id: String {
        switch self {
        case .contentUnavailable: "contentUnavailable"
        case .writeFailed: "writeFailed"
        }
    }

    var message: String {
        switch self {
        case .contentUnavailable: "This stage's content isn't available right now. Try again in a moment."
        case .writeFailed: "Couldn't reach the server. Try again."
        }
    }
}

#Preview {
    let pathRepo = PathRepository.preview()
    let track = pathRepo.tracks(for: .junior)[1] // junior-02, "Object-oriented Swift"
    return NavigationStack {
        TrackLadderView(track: track)
    }
    .environment(ProfileRepository.preview())
    .environment(pathRepo)
    .environment(AuthRepository(isPreview: true, signedIn: true))
}
