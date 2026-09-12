import SwiftUI

struct InterviewBankView: View {
    @Environment(InterviewRepository.self) private var repo
    @Environment(AuthRepository.self) private var authRepo
    @State private var levelFilter = "All"
    @State private var searchText = ""

    /// Junior/mid/senior take the design's own press-plate progression (pink, yellow, black)
    /// instead of the default accent, so the level filter itself recolors the screen.
    private var levelAccent: Color {
        switch levelFilter {
        case "Junior": Theme.Colors.accent2
        case "Mid": Theme.Colors.processYellow
        case "Senior": Theme.Colors.text
        default: Theme.Colors.accent
        }
    }

    private var levelAccentForeground: Color {
        levelFilter == "Mid" ? Theme.Colors.text : Theme.Colors.bg
    }

    var body: some View {
        Group {
            if repo.isLoading && repo.categories.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                bankContent
            }
        }
        .background(Theme.Colors.bg)
        .task {
            async let content: Void = repo.categories.isEmpty ? repo.load() : ()
            if let uid = authRepo.currentUser?.uid {
                async let userState: Void = repo.loadUserState(for: uid)
                _ = await (content, userState)
            } else {
                _ = await content
            }
        }
    }

    private var bankContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline) {
                    EyebrowLabel("Interview prep")
                    Spacer()
                    Text("Bookmarks · \(repo.questions.filter(repo.isBookmarked).count)")
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

                SegmentedPicker(
                    options: ["All", "Junior", "Mid", "Senior"], selection: $levelFilter,
                    selectedFill: levelAccent, selectedForeground: levelAccentForeground
                )
                    .padding(.top, 12)

                VStack(spacing: 0) {
                    ForEach(Array(repo.categories.enumerated()), id: \.element.id) { index, category in
                        categoryRow(category, isLast: index == repo.categories.count - 1)
                    }
                }
                .padding(.top, 22)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: InterviewCategoryContent, isLast: Bool) -> some View {
        let questions = category.questions(for: levelFilter)
        if !questions.isEmpty {
            NavigationLink {
                FlashcardSessionView(category: category.name, level: levelFilter, repo: repo)
            } label: {
                RuledRow(showBottomRule: isLast, minHeight: 56) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name).font(Theme.Fonts.heading(16.5))
                        Text(reviewedLabel(for: questions))
                            .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        } else {
            RuledRow(showBottomRule: isLast, minHeight: 56) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name).font(Theme.Fonts.heading(16.5))
                        .foregroundStyle(Theme.Colors.neutral400)
                    Text(emptyLabel(for: levelFilter))
                        .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral400)
                }
                Spacer()
            }
        }
    }

    private func reviewedLabel(for questions: [InterviewQuestion]) -> String {
        let reviewed = questions.filter(repo.hasBeenReviewed).count
        return "\(reviewed) of \(questions.count) reviewed"
    }

    private func emptyLabel(for level: String) -> String {
        level == "All" ? "No questions yet" : "No \(level) questions yet"
    }
}

#Preview {
    NavigationStack { InterviewBankView() }
        .environment(InterviewRepository.preview())
}
