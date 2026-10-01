import SwiftUI

/// Thin wrapper around `LibraryQuizView` for the grade regrade quiz — unrelated to Library access
/// now (grade gates nothing there), a separate status/achievement ladder. Fetched on appear rather
/// than passed in, since the caller only knows the *grade*, not its quiz content.
struct RegradeQuizView: View {
    @Environment(LibraryRepository.self) private var libraryRepo
    @Environment(AuthRepository.self) private var authRepo
    @Environment(\.dismiss) private var dismiss
    let grade: SkillLevel

    @State private var quiz: RegradeQuiz?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let quiz {
                LibraryQuizView(
                    title: "Regrade quiz",
                    questions: quiz.questions,
                    onPassed: { _ in },
                    onFinished: {
                        Task {
                            if let uid = authRepo.currentUser?.uid {
                                await libraryRepo.promoteGrade(from: grade, for: uid)
                            }
                            dismiss()
                        }
                    },
                    onAbandon: { dismiss() }
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
            quiz = await libraryRepo.fetchRegradeQuiz(for: grade)
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        RegradeQuizView(grade: .junior)
    }
    .environment(LibraryRepository.preview())
    .environment(AuthRepository(isPreview: true, signedIn: true))
}
