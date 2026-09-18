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

    /// Side-effect-free on purpose: this type is typically constructed as a `@State` default
    /// value (`@State private var adPresenter = AdMobRewardedAdPresenter()`), and SwiftUI does
    /// NOT guarantee a `@State` default-value expression runs only once — only that its storage
    /// is initialized once. An `init` that kicks off a network load got evaluated 4 times at a
    /// single launch in testing, each one starting its own independent, mostly-wasted ad load.
    /// The real preload is triggered explicitly via `preload()`, called from the owning view's
    /// `.task` — which SwiftUI does guarantee runs exactly once per view identity.
    init(adUnitID: String = AdMobRewardedAdPresenter.testAdUnitID) {
        self.adUnitID = adUnitID
    }

    func preload() async {
        await loadAd()
    }

    @MainActor
    func presentAd(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard let rewardedAd else {
            completion(true)
            Task { await loadAd() }
            return
        }
        guard let root = Self.topViewController() else {
            completion(true)
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

    /// Walks down the `presentedViewController` chain to the true frontmost VC — presenting from
    /// a mere `.rootViewController` can silently no-op if anything (a sheet, another modal) is
    /// already presented on top of it.
    private static func topViewController() -> UIViewController? {
        var top = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
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
