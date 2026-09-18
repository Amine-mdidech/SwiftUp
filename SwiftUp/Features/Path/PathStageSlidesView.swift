import SwiftUI

/// A lesson stage's slide deck, paged Next/Back. On the last slide, "Next" becomes "Start the
/// quiz" and pushes `PathQuizView` fed this stage's `content.quiz` — `onPassed`/`onFinished` are
/// threaded straight through to that nested view unchanged, so whichever pushed this view (only
/// `TrackLadderView`, for a lesson-kind stage) can pop all the way back with one state reset when
/// `onFinished` fires, regardless of whether that happens from the slides or from the quiz nested
/// beneath them.
struct PathStageSlidesView: View {
    let stage: PathStage
    let content: PathStageContent
    let onPassed: () async -> Void
    let onFinished: () -> Void

    @State private var session: PathLessonSession
    @State private var showQuiz = false

    init(stage: PathStage, content: PathStageContent, onPassed: @escaping () async -> Void, onFinished: @escaping () -> Void) {
        self.stage = stage
        self.content = content
        self.onPassed = onPassed
        self.onFinished = onFinished
        _session = State(initialValue: PathLessonSession(slides: content.slides))
    }

    var body: some View {
        Group {
            if let slide = session.currentSlide {
                slideContent(slide)
            }
        }
        .padding(24)
        .background(Theme.Colors.bg)
        .navigationBarBackButtonHidden()
        .navigationDestination(isPresented: $showQuiz) {
            PathQuizView(
                title: stage.title,
                questions: content.quiz,
                onPassed: onPassed,
                onFinished: onFinished
            )
        }
    }

    private func slideContent(_ slide: PathSlide) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(stage.title).font(.system(size: 11)).foregroundStyle(Theme.Colors.neutral700)
                Spacer()
                Text("Slide \(slide.order) / \(session.slides.count)")
                    .font(.system(size: 10)).foregroundStyle(Theme.Colors.neutral700)
            }

            Text(slide.title)
                .font(Theme.Fonts.heading(26))
                .foregroundStyle(Theme.Colors.text)
                .padding(.top, 30)

            Text(slide.body)
                .font(Theme.Fonts.body(15.5))
                .foregroundStyle(Theme.Colors.neutral800)
                .padding(.top, 16)

            if let example = slide.example {
                Text(example)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)
                    .padding(.top, 20)
            }

            Spacer(minLength: 20)

            HStack(spacing: 12) {
                Button("Back") { session.goBack() }
                    .disabled(session.isFirstSlide)
                    .frame(minHeight: 44)
                Spacer()
                Button(action: {
                    if session.isLastSlide {
                        showQuiz = true
                    } else {
                        session.advance()
                    }
                }) {
                    Text(session.isLastSlide ? "Start the quiz" : "Next")
                        .font(Theme.Fonts.heading(17))
                        .frame(maxWidth: 200)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
            }
        }
    }
}

#Preview {
    let content = PathStageContent(
        stageID: "preview-s01",
        slides: [
            PathSlide(id: "s1", order: 1, title: "Value semantics", body: "Structs copy on assignment.", example: nil),
            PathSlide(id: "s2", order: 2, title: "Value semantics", body: "Classes share a reference.", example: "let a = Point(); let b = a"),
        ],
        quiz: [
            PathQuizQuestion(
                id: "q1", prompt: "Preview question?",
                options: [QuestionOption(id: "A", text: "Correct answer"), QuestionOption(id: "B", text: "Incorrect answer 1")],
                correctOptionID: "A"
            )
        ]
    )
    let stage = PathStage(id: "preview-s01", order: 1, title: "Value semantics", xpCost: 50, kind: .lesson)
    return NavigationStack {
        PathStageSlidesView(stage: stage, content: content, onPassed: {}, onFinished: {})
    }
}
