import SwiftUI

struct OnboardingFlowView: View {
    enum Step { case welcome, skill }

    @Environment(QuestionRepository.self) private var questionRepository
    @Environment(AuthRepository.self) private var authRepository
    @State private var step: Step = .welcome
    let onComplete: () -> Void

    var body: some View {
        switch step {
        case .welcome:
            WelcomeView(onContinue: { step = .skill })
        case .skill:
            SkillAssessmentView(onContinue: { level in
                if let uid = authRepository.currentUser?.uid {
                    Task { await questionRepository.saveInitialSkillLevel(level, for: uid) }
                }
                onComplete()
            })
        }
    }
}

#Preview {
    OnboardingFlowView(onComplete: {})
        .environment(QuestionRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
