import Foundation

/// Gate for showing an ad before an optional, non-essential action — currently only the
/// past-editions practice redo (`TodayFlowView.startReplay`). Deliberately not tied to any ad SDK:
/// swapping in a real rewarded-ad implementation later means adding one new conforming type and
/// constructing `TodayFlowView` with it — nothing about the redo flow itself changes.
protocol RewardedAdPresenting {
    /// `completion(true)` if the ad played (or there was nothing to block on) and the gated action
    /// should proceed; `completion(false)` to abandon it (e.g. the user backed out of the ad).
    /// Called on the main actor — `startReplay`'s closure mutates SwiftUI `@State` directly inside
    /// this callback, so any real conforming type (a future ad SDK wrapper) must hop back to the
    /// main actor before invoking `completion`, not assume it's already there.
    func presentAd(completion: @escaping @MainActor @Sendable (Bool) -> Void)
}

/// Today's stand-in — always proceeds immediately. No ad SDK is integrated yet.
struct NoOpAdPresenter: RewardedAdPresenting {
    @MainActor
    func presentAd(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        print("[AdPresenter] NoOpAdPresenter.presentAd called — this means adPresenter is NOT the real AdMobRewardedAdPresenter")
        completion(true)
    }
}
