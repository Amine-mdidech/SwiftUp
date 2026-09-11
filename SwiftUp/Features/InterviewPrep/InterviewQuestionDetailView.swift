import SwiftUI

struct InterviewQuestionDetailView: View {
    @Environment(InterviewRepository.self) private var repo
    @State var question: InterviewQuestion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("← \(question.category)").font(Theme.Fonts.body(15)).foregroundStyle(Theme.Colors.accent700)
                    Spacer()
                    Text(question.bookmarked ? "★ Bookmarked" : "☆ Bookmark")
                        .font(.system(size: 13)).foregroundStyle(Theme.Colors.accent700)
                }

                HStack(spacing: 8) {
                    Text(question.difficulty)
                        .font(.system(size: 11))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Theme.Colors.accent100).foregroundStyle(Theme.Colors.accent800)
                    if let position = repo.position(of: question) {
                        EyebrowLabel("Question \(position.index) of \(position.total)")
                    }
                }
                .padding(.top, 12)

                Text(question.prompt).font(Theme.Fonts.heading(27)).padding(.top, 14)

                EyebrowLabel("Model answer", color: Theme.Colors.accent700).padding(.top, 24)
                Text(question.modelAnswer).font(Theme.Fonts.body(15)).padding(.top, 10)

                EyebrowLabel("Talking points").padding(.top, 22)
                VStack(spacing: 0) {
                    ForEach(Array(question.talkingPoints.enumerated()), id: \.offset) { index, point in
                        RuledRow(showBottomRule: index == question.talkingPoints.count - 1, minHeight: 0) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.accent700)
                            Text(point).font(Theme.Fonts.body(14))
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.top, 10)

                EyebrowLabel("Follow-ups they ask next").padding(.top, 22)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(question.followUps, id: \.self) { followUp in
                        Text("— \(followUp)").font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral800)
                    }
                }
                .padding(.top, 10)

                HStack(spacing: 12) {
                    Button {} label: {
                        Text("Mark reviewed")
                            .font(.system(size: 15.5))
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))
                    Button {
                        if let next = repo.nextQuestion(after: question) {
                            question = next
                        }
                    } label: {
                        Text("Next question")
                            .font(.system(size: 15.5))
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                    }
                    .background(Theme.Colors.accent)
                    .foregroundStyle(Theme.Colors.bg)
                }
                .padding(.top, 26)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview {
    let repo = InterviewRepository.preview()
    return NavigationStack {
        InterviewQuestionDetailView(question: repo.questions[0])
    }
    .environment(repo)
}
