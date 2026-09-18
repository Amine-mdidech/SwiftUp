import SwiftUI

/// Thin wrapper around `PathQuizView` for the grade regrade quiz — free to start (closing every
/// track in the grade is the only unlock condition, design doc §6), fetched on appear rather than
/// passed in, since `PathWheelView` only knows the *grade*, not its quiz content.
struct PathRegradeQuizView: View {
    @Environment(PathRepository.self) private var pathRepo
    @Environment(AuthRepository.self) private var authRepo
    @Environment(\.dismiss) private var dismiss
    let grade: SkillLevel

    @State private var quiz: PathRegradeQuiz?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let quiz {
                PathQuizView(
                    title: "Regrade quiz",
                    session: PathQuizSession(questions: quiz.questions),
                    onPassed: {
                        guard let uid = authRepo.currentUser?.uid else { return }
                        await pathRepo.promoteGrade(from: grade, for: uid)
                    },
                    onFinished: { dismiss() }
                )
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.bg)
            } else {
                VStack {
                    Text("This grade's regrade quiz isn't available right now.")
                        .font(Theme.Fonts.body(15))
                        .multilineTextAlignment(.center)
                    Button("Back") { dismiss() }.padding(.top, 16)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.bg)
            }
        }
        .task {
            quiz = await pathRepo.fetchRegradeQuiz(for: grade)
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        PathRegradeQuizView(grade: .junior)
    }
    .environment(PathRepository.preview())
    .environment(AuthRepository(isPreview: true, signedIn: true))
}
