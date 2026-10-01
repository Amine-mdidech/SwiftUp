import SwiftUI

struct DailyQuizEntryView: View {
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(QuestionRepository.self) private var questionRepo
    @Environment(AuthRepository.self) private var authRepo
    /// `nil` until the user taps a grade, meaning "show whatever `questionRepo.effectiveLevel`
    /// already is." Once set, it wins over `effectiveLevel` for the rest of this screen's
    /// lifetime — the tap reads back instantly (this `@State` flips synchronously) regardless of
    /// how long the background `setLevelOverride` write takes, matching the optimistic-then-persist
    /// pattern `SettingsView`'s own difficulty picker already uses.
    @State private var selectedLevel: SkillLevel?
    let onBegin: (SkillLevel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RuledMasthead(left: DailyEdition.dateLabel(), right: editionLabel)

            gradeSwitcher
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 12) {
                EyebrowLabel("The daily five", color: Theme.Colors.accent700)
                headline
                Text("Five questions, drawn this morning. About three minutes.")
                    .font(Theme.Fonts.body(16))
                    .foregroundStyle(Theme.Colors.neutral700)
            }
            .padding(.top, 20)

            topicBreakdown
                .padding(.top, 22)

            Spacer()

            HStack(alignment: .bottom, spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    EyebrowLabel("Streak")
                    PlateNumeral("\(profileRepo.profile.streakDays)", font: Theme.Fonts.heading(64))
                    Text("days · \(profileRepo.profile.freezesAvailable) \(profileRepo.profile.freezesAvailable == 1 ? "freeze" : "freezes") held")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.neutral600)
                }
                VStack(alignment: .leading, spacing: 10) {
                    EyebrowLabel("XP")
                    PlateNumeral("\(profileRepo.profile.xp)", font: Theme.Fonts.heading(64))
                    Text("lifetime total")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.Colors.neutral600)
                }
            }

            if displayedQuestions.isEmpty {
                Text("No questions available right now — check back soon.")
                    .font(Theme.Fonts.body(13))
                    .foregroundStyle(Theme.Colors.neutral600)
                    .padding(.top, 12)
            }

            Button(action: { onBegin(displayedLevel) }) {
                Text("Begin today's five")
                    .font(Theme.Fonts.heading(17))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .background(Theme.Colors.accent)
            .foregroundStyle(Theme.Colors.bg)
            .padding(.top, 30)
            .disabled(displayedQuestions.isEmpty)
        }
        .padding(24)
        .background(Theme.Colors.bg)
    }

    private var displayedLevel: SkillLevel { selectedLevel ?? questionRepo.effectiveLevel }
    private var displayedQuestions: [Question] { questionRepo.questions(for: displayedLevel) }

    private var gradeSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(SkillLevel.allCases) { level in
                gradeChip(level)
            }
        }
    }

    private func gradeChip(_ level: SkillLevel) -> some View {
        let isSelected = level == displayedLevel
        return Text(level.displayName)
            .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? Theme.Colors.text : Color.clear)
            .foregroundStyle(isSelected ? Theme.Colors.bg : Theme.Colors.text)
            .overlay(Rectangle().stroke(isSelected ? Theme.Colors.text : Theme.Colors.divider, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { selectLevel(level) }
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func selectLevel(_ level: SkillLevel) {
        guard level != displayedLevel else { return }
        selectedLevel = level
        guard let uid = authRepo.currentUser?.uid else { return }
        Task { await questionRepo.setLevelOverride(level, for: uid) }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Five").font(Theme.Fonts.heading(40))
            Text(displayedLevel.displayName).font(Theme.Fonts.heading(40)).foregroundStyle(Theme.Colors.accent700)
            Text("questions.").font(Theme.Fonts.heading(40))
        }
    }

    /// Topics in the order their questions appear in today's quiz (the same order
    /// `QuizQuestionView` will present them) — not alphabetical or by count, so the breakdown reads
    /// as a preview of the actual run rather than an arbitrary sort.
    private var topicBreakdown: some View {
        VStack(spacing: 0) {
            ForEach(Array(groupedTopics.enumerated()), id: \.offset) { index, entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.neutral700)
                        .frame(width: 20, alignment: .leading)
                    Text(entry.topic).font(Theme.Fonts.body(14.5))
                    Spacer()
                    EyebrowLabel(entry.count == 1 ? "1 question" : "\(entry.count) questions")
                }
                .padding(.vertical, 9)
                .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
                .overlay(
                    index == groupedTopics.count - 1
                        ? Rectangle().fill(Theme.Colors.divider).frame(height: 1) : nil,
                    alignment: .bottom
                )
            }
        }
    }

    private var groupedTopics: [(topic: String, count: Int)] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for question in displayedQuestions {
            if counts[question.topic] == nil { order.append(question.topic) }
            counts[question.topic, default: 0] += 1
        }
        return order.map { (topic: $0, count: counts[$0]!) }
    }

    private var editionLabel: String {
        questionRepo.editionNumber.map { "Edition \($0)" } ?? "Edition —"
    }
}

#Preview {
    DailyQuizEntryView(onBegin: { _ in })
        .environment(ProfileRepository.preview())
        .environment(QuestionRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
