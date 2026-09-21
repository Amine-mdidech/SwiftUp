import SwiftUI

struct RootView: View {
    @State private var showSplash = true

    @State private var questionRepository = QuestionRepository()
    @State private var profileRepository = ProfileRepository()
    @State private var interviewRepository = InterviewRepository()
    @State private var pathRepository = PathRepository()
    @State private var authRepository = AuthRepository()

    var body: some View {
        Group {
            if showSplash {
                SplashView(onFinished: { showSplash = false })
            } else if authRepository.isSignedIn {
                switch authRepository.hasCompletedOnboarding {
                case true:
                    MainTabView()
                case false:
                    OnboardingFlowView(onComplete: { authRepository.markOnboardingCompleted() })
                case nil:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.Colors.bg)
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
        .environment(pathRepository)
        .environment(authRepository)
    }
}

#Preview {
    RootView()
}
