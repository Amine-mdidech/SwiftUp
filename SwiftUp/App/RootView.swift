import SwiftUI

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showSplash = true

    @State private var questionRepository = QuestionRepository()
    @State private var profileRepository = ProfileRepository()
    @State private var interviewRepository = InterviewRepository()
    @State private var leaderboardRepository = LeaderboardRepository()
    @State private var pathRepository = PathRepository()
    @State private var authRepository = AuthRepository()

    var body: some View {
        Group {
            if showSplash {
                SplashView(onFinished: { showSplash = false })
            } else if authRepository.isSignedIn {
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
        .environment(pathRepository)
        .environment(authRepository)
    }
}

#Preview {
    RootView()
}
