import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                TodayFlowView()
                    .tag(AppTab.today)
                NavigationStack { InterviewBankView() }
                    .tag(AppTab.prep)
                NavigationStack { LeaderboardView() }
                    .tag(AppTab.ranks)
                NavigationStack { ProfileHomeView() }
                    .tag(AppTab.record)
            }
            .toolbar(.hidden, for: .tabBar)
            CustomTabBar(selection: $selectedTab)
        }
    }
}

#Preview {
    MainTabView()
        .environment(QuestionRepository())
        .environment(ProfileRepository())
        .environment(InterviewRepository())
        .environment(LeaderboardRepository())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
