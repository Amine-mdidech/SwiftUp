import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                TodayFlowView()
                    .opacity(selectedTab == .today ? 1 : 0)
                    .allowsHitTesting(selectedTab == .today)
                NavigationStack { InterviewBankView() }
                    .opacity(selectedTab == .prep ? 1 : 0)
                    .allowsHitTesting(selectedTab == .prep)
                NavigationStack { LeaderboardView() }
                    .opacity(selectedTab == .ranks ? 1 : 0)
                    .allowsHitTesting(selectedTab == .ranks)
                NavigationStack { ProfileHomeView() }
                    .opacity(selectedTab == .record ? 1 : 0)
                    .allowsHitTesting(selectedTab == .record)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            CustomTabBar(selection: $selectedTab)
        }
    }
}

#Preview {
    MainTabView()
        .environment(QuestionRepository.preview())
        .environment(ProfileRepository.preview())
        .environment(InterviewRepository.preview())
        .environment(LeaderboardRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
