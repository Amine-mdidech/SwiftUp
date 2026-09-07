import SwiftUI

struct OnboardingFlowView: View {
    enum Step { case welcome, skill, topics }

    @State private var step: Step = .welcome
    let onComplete: () -> Void

    var body: some View {
        switch step {
        case .welcome:
            WelcomeView(onContinue: { step = .skill })
        case .skill:
            SkillAssessmentView(onContinue: { _ in step = .topics })
        case .topics:
            TopicInterestsView(onFinish: onComplete)
        }
    }
}

#Preview {
    OnboardingFlowView(onComplete: {})
}
