import SwiftUI

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let questionRepository = QuestionRepository()
    private let profileRepository = ProfileRepository()
    private let interviewRepository = InterviewRepository()
    private let leaderboardRepository = LeaderboardRepository()
    @State private var authRepository = AuthRepository()

    var body: some View {
        Group {
            if authRepository.isSignedIn {
                if hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingFlowView(onComplete: { hasCompletedOnboarding = true })
                }
            } else {
                NavigationStack {
                    AuthView()
                }
            }
        }
        .environment(questionRepository)
        .environment(profileRepository)
        .environment(interviewRepository)
        .environment(leaderboardRepository)
        .environment(authRepository)
    }
}

#Preview {
    RootView()
}
