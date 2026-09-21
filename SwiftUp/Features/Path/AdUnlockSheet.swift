import SwiftUI

/// Presented from `TrackLadderView` when `PathRepository.startStage` returns `.insufficientXP`.
/// `canWatchAd` reflects `PathRepository.hasAdUnlockAvailableToday` at the moment the sheet opens
/// — once per calendar day, regardless of which stage. `onWatchAd` fires only when the ad option
/// is tappable; the sheet dismisses itself immediately after, letting the caller present the ad
/// without a sheet still on screen.
struct AdUnlockSheet: View {
    let stage: PathStage
    let balance: Int
    let canWatchAd: Bool
    let onWatchAd: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Rectangle().fill(Theme.Colors.text).frame(height: 3)

            Text(canWatchAd ? "Not quite enough xp" : "Already unlocked today")
                .font(Theme.Fonts.heading(24))
                .padding(.top, 8)

            if canWatchAd {
                Text("You have \(balance) xp — \"\(stage.title)\" costs \(stage.xpCost). Watch a short ad to unlock it for free.")
                    .font(Theme.Fonts.body(15))
                    .foregroundStyle(Theme.Colors.neutral800)

                Button(action: {
                    onWatchAd()
                    dismiss()
                }) {
                    Text("Watch an ad to unlock")
                        .font(Theme.Fonts.heading(17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)

                Text("Once a day.")
                    .font(Theme.Fonts.body(12.5))
                    .foregroundStyle(Theme.Colors.neutral700)
            } else {
                Text("You've already used today's free unlock. Come back tomorrow, or earn more xp from the daily five.")
                    .font(Theme.Fonts.body(15))
                    .foregroundStyle(Theme.Colors.neutral800)
            }

            Button("Close") { dismiss() }
                .font(.system(size: 15))
                .foregroundStyle(Theme.Colors.accent700)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(Theme.Colors.bg)
    }
}

#Preview("Can watch ad") {
    AdUnlockSheet(
        stage: PathStage(id: "s1", order: 1, title: "Object-oriented Swift", xpCost: 200, kind: .lesson),
        balance: 40, canWatchAd: true, onWatchAd: {}
    )
}

#Preview("Already used today") {
    AdUnlockSheet(
        stage: PathStage(id: "s1", order: 1, title: "Object-oriented Swift", xpCost: 200, kind: .lesson),
        balance: 40, canWatchAd: false, onWatchAd: {}
    )
}
