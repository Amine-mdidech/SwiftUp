import SwiftUI

struct OnboardingFlowView: View {
    @Environment(QuestionRepository.self) private var questionRepository
    @Environment(AuthRepository.self) private var authRepository
    let onComplete: () -> Void

    var body: some View {
        SkillAssessmentView(onContinue: { level in
            if let uid = authRepository.currentUser?.uid {
                Task { await questionRepository.saveInitialSkillLevel(level, for: uid) }
            }
            onComplete()
        })
    }
}

#Preview {
    OnboardingFlowView(onComplete: {})
        .environment(QuestionRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
