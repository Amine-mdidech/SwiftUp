import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .today
    // `@State`, not constructed inline in `body`: `body` re-evaluates on every tab switch (this
    // view's own `selectedTab` is `@State`), and a fresh `AdMobRewardedAdPresenter()` each time
    // would restart its preload cycle and orphan any in-flight ad load every time the user just
    // switched tabs.
    @State private var adPresenter = AdMobRewardedAdPresenter()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                TodayFlowView(adPresenter: adPresenter)
                    .opacity(selectedTab == .today ? 1 : 0)
                    .allowsHitTesting(selectedTab == .today)
                NavigationStack { InterviewBankView() }
                    .opacity(selectedTab == .prep ? 1 : 0)
                    .allowsHitTesting(selectedTab == .prep)
                NavigationStack { LibraryView() }
                    .opacity(selectedTab == .library ? 1 : 0)
                    .allowsHitTesting(selectedTab == .library)
                NavigationStack { ProfileHomeView() }
                    .opacity(selectedTab == .record ? 1 : 0)
                    .allowsHitTesting(selectedTab == .record)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            CustomTabBar(selection: $selectedTab)
        }
        .task { await adPresenter.preload() }
    }
}

#Preview {
    MainTabView()
        .environment(QuestionRepository.preview())
        .environment(ProfileRepository.preview())
        .environment(InterviewRepository.preview())
        .environment(LibraryRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
