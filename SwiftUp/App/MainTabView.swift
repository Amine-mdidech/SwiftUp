import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .today:
                    TodayFlowView()
                case .prep:
                    NavigationStack { InterviewBankView() }
                case .ranks:
                    NavigationStack { LeaderboardView() }
                case .record:
                    NavigationStack { ProfileHomeView() }
                }
            }
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
}
