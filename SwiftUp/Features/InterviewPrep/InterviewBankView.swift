import SwiftUI

struct InterviewBankView: View {
    @Environment(InterviewRepository.self) private var repo
    @State private var levelFilter = "All"
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline) {
                    EyebrowLabel("Interview prep")
                    Spacer()
                    Text("Bookmarks · \(repo.questions.filter(\.bookmarked).count)")
                        .font(.system(size: 13)).foregroundStyle(Theme.Colors.accent700)
                }

                Text("The question\nbank").font(Theme.Fonts.heading(32)).padding(.top, 8)
                Text("\(repo.questions.count) questions with model answers, talking points and the follow-ups they usually attract.")
                    .font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 12)

                TextField("Search the bank", text: $searchText)
                    .padding(.horizontal, 10).padding(.vertical, 10)
                    .background(Theme.Colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))
                    .padding(.top, 18)

                SegmentedPicker(options: ["All", "Junior", "Mid", "Senior"], selection: $levelFilter)
                    .padding(.top, 12)

                VStack(spacing: 0) {
                    ForEach(Array(repo.categories.enumerated()), id: \.element.id) { index, category in
                        NavigationLink {
                            if let first = repo.firstQuestion(in: category.name) {
                                InterviewQuestionDetailView(question: first)
                            }
                        } label: {
                            RuledRow(showBottomRule: index == repo.categories.count - 1, minHeight: 56) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(category.name).font(Theme.Fonts.heading(16.5))
                                    Text("\(category.reviewedCount) of \(category.totalCount) reviewed")
                                        .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
                                }
                                Spacer()
                                ThinProgressBar(
                                    fraction: Double(category.reviewedCount) / Double(max(1, category.totalCount)),
                                    fillColor: category.reviewedCount == 0 ? Theme.Colors.neutral200 : Theme.Colors.accent
                                )
                                .frame(width: 64)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 22)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview {
    NavigationStack { InterviewBankView() }
        .environment(InterviewRepository())
}
