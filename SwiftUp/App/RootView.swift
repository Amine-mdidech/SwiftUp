import SwiftUI

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let questionRepository = QuestionRepository()
    private let profileRepository = ProfileRepository()
    private let interviewRepository = InterviewRepository()
    private let leaderboardRepository = LeaderboardRepository()

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingFlowView(onComplete: { hasCompletedOnboarding = true })
            }
        }
        .environment(questionRepository)
        .environment(profileRepository)
        .environment(interviewRepository)
        .environment(leaderboardRepository)
    }
}

#Preview {
    RootView()
}
