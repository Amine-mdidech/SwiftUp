import Foundation
import GoogleMobileAds
import UIKit

/// Real `RewardedAdPresenting` conformance, backed by the Google Mobile Ads SDK. Preloads a
/// rewarded ad eagerly and again after every present (earned, declined, or failed) so there's
/// usually one warm and ready by the time a user taps a day to redo.
///
/// Fails open: if no ad happens to be ready (still loading, or the last load failed — e.g. thin
/// fill on a brand-new app), `presentAd` proceeds without blocking the redo, matching
/// `TodayFlowView.startReplay`'s existing "quiet no-op" behavior elsewhere on this screen.
final class AdMobRewardedAdPresenter: NSObject, RewardedAdPresenting {
    /// Google's published sample rewarded-ad unit ID — always fills with a test ad, never earns
    /// real money. Swap for your real ad unit ID once you register this app in AdMob.
    static let testAdUnitID = "ca-app-pub-3940256099942544/1712485313"

    private let adUnitID: String
    private var rewardedAd: RewardedAd?
    private var pendingCompletion: (@MainActor @Sendable (Bool) -> Void)?
    private var didEarnReward = false

    init(adUnitID: String = AdMobRewardedAdPresenter.testAdUnitID) {
        self.adUnitID = adUnitID
        super.init()
        Task { await loadAd() }
    }

    @MainActor
    func presentAd(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard let rewardedAd, let root = Self.topViewController() else {
            completion(true)
            Task { await loadAd() }
            return
        }
        didEarnReward = false
        pendingCompletion = completion
        rewardedAd.fullScreenContentDelegate = self
        rewardedAd.present(from: root) { [weak self] in
            self?.didEarnReward = true
        }
    }

    private func loadAd() async {
        do {
            rewardedAd = try await RewardedAd.load(with: adUnitID, request: Request())
        } catch {
            rewardedAd = nil
        }
    }

    private static func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

extension AdMobRewardedAdPresenter: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        rewardedAd = nil
        let completion = pendingCompletion
        let earned = didEarnReward
        pendingCompletion = nil
        Task { @MainActor in completion?(earned) }
        Task { await loadAd() }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        rewardedAd = nil
        let completion = pendingCompletion
        pendingCompletion = nil
        Task { @MainActor in completion?(true) }
        Task { await loadAd() }
    }
}
