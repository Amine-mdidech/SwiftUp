import SwiftUI

/// A class's article — every one of its slides concatenated into a single scroll, replacing the
/// old paginated Next/Back slide deck (source design turn 16c: "a class is an article, not a
/// slideshow"). Same underlying `LibrarySlide` content and order, just read straight through instead
/// of tapped through page by page. Ends with a button into `LibraryQuizView` fed this class's
/// quiz — `onPassed`/`onFinished` are threaded straight through to that nested view unchanged, so
/// whichever pushed this view can pop all the way back with one state reset when `onFinished`
/// fires, regardless of whether that happens from here or from the quiz nested beneath.
struct ClassArticleView: View {
    let path: LibraryPath
    let libClass: LibraryClass
    let content: LibraryClassContent
    let onPassed: (Bool) async -> Void
    let onFinished: () -> Void
    let onAbandon: () -> Void

    @State private var showQuiz = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button("← \(path.title)") { onAbandon() }
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.accent700)
                    Spacer()
                    Text("\(estimatedReadMinutes) min read")
                        .font(.system(size: 10)).foregroundStyle(Theme.Colors.neutral700)
                }
                .frame(minHeight: 44)

                EyebrowLabel("\(path.grade.volumeNumeral).\(path.order).\(libClass.order)")
                    .padding(.top, 10)

                Text(libClass.title)
                    .font(Theme.Fonts.heading(28))
                    .foregroundStyle(Theme.Colors.text)
                    .padding(.top, 8)

                ForEach(content.slides.sorted { $0.order < $1.order }) { slide in
                    slideSection(slide)
                }

                Button(action: { showQuiz = true }) {
                    Text("Take the quiz · \(content.quiz.count) questions")
                        .font(Theme.Fonts.heading(17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
                .padding(.top, 30)

                Text("Scores count toward topic accuracy.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Colors.neutral700)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
        .navigationBarBackButtonHidden()
        .navigationDestination(isPresented: $showQuiz) {
            LibraryQuizView(
                title: libClass.title,
                questions: content.quiz,
                onPassed: onPassed,
                onFinished: onFinished,
                onAbandon: onAbandon
            )
        }
    }

    private func slideSection(_ slide: LibrarySlide) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(slide.title)
                .font(Theme.Fonts.heading(18))
                .padding(.top, 26)

            Text(slide.body)
                .font(Theme.Fonts.body(15))
                .foregroundStyle(Theme.Colors.neutral800)
                .padding(.top, 8)

            if let example = slide.example {
                Text(example)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)
                    .padding(.top, 14)
            }
        }
    }

    /// A rough estimate (~200 words/minute), since slide content has no authored read-time field.
    private var estimatedReadMinutes: Int {
        let wordCount = content.slides.reduce(0) { $0 + $1.body.split(separator: " ").count }
        return max(1, (wordCount + 99) / 200)
    }
}

#Preview {
    let path = LibraryPath(
        id: "preview", grade: .mid, order: 1, title: "Concurrency",
        summary: "Running work at the same time without data races.", classes: []
    )
    let libClass = LibraryClass(id: "preview-s01", order: 1, title: "Value semantics", xpReward: 50, kind: .lesson)
    let content = LibraryClassContent(
        classID: "preview-s01",
        slides: [
            LibrarySlide(id: "s1", order: 1, title: "Value semantics", body: "Structs copy on assignment.", example: nil),
            LibrarySlide(id: "s2", order: 2, title: "Reference semantics", body: "Classes share a reference.", example: "let a = Point(); let b = a"),
        ],
        quiz: [
            LibraryQuizQuestion(
                id: "q1", prompt: "Preview question?",
                options: [QuestionOption(id: "A", text: "Correct answer"), QuestionOption(id: "B", text: "Incorrect answer 1")],
                correctOptionID: "A",
                explanation: "This is a placeholder explanation."
            )
        ]
    )
    return NavigationStack {
        ClassArticleView(path: path, libClass: libClass, content: content, onPassed: { _ in }, onFinished: {}, onAbandon: {})
    }
}
