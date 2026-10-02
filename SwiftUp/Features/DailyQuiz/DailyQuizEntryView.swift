import SwiftUI

/// A day's shared quiz offered as a practice redo (from `QuizEditionsView`), already loaded so the
/// entry screen can show its topics and grades before anything starts. Today's own quiz uses
/// `questionRepo` directly instead and never builds one of these.
struct PracticeEdition {
    let dateKey: String
    let edition: Int?
    let questionsByLevel: [SkillLevel: [Question]]

    init(dateKey: String, edition: Int?, questions: (SkillLevel) -> [Question]) {
        self.dateKey = dateKey
        self.edition = edition
        questionsByLevel = Dictionary(uniqueKeysWithValues: SkillLevel.allCases.map { ($0, questions($0)) })
    }

    func questions(for level: SkillLevel) -> [Question] { questionsByLevel[level] ?? [] }

    /// Grades worth offering: those with questions. An older document can carry only some sets, or
    /// fall back to the same set for several grades (see `DailyQuizDocument.distinguished`).
    var levels: [SkillLevel] { SkillLevel.allCases.filter { !questions(for: $0).isEmpty } }

    /// `false` when every offered grade would serve the same questions, so there's nothing to pick.
    var hasDifficultyChoice: Bool {
        Set(levels.map { questions(for: $0).map(\.id) }).count > 1
    }

    var isToday: Bool { dateKey == DailyEdition.todayKey() }
}

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
    /// `nil` for today's real quiz; set for a practice redo of an already-loaded day.
    var practice: PracticeEdition? = nil
    let onBegin: (SkillLevel) -> Void
    /// Shown as a back link when set — practice entries return to the editions overview.
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onBack {
                Button("← Back to editions", action: onBack)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.accent700)
                    .frame(minHeight: 44)
                    .padding(.bottom, 4)
            }

            RuledMasthead(left: dateLabel, right: editionLabel)

            if showsGradeSwitcher {
                gradeSwitcher
                    .padding(.top, 16)
            }

            VStack(alignment: .leading, spacing: 12) {
                EyebrowLabel(practice == nil ? "The daily five" : "Practice · 0 xp", color: Theme.Colors.accent700)
                headline
                Text(practice == nil
                    ? "Five questions, drawn this morning. About three minutes."
                    : "Just for you — doesn't count toward xp, accuracy, or your streak.")
                    .font(Theme.Fonts.body(16))
                    .foregroundStyle(Theme.Colors.neutral700)
            }
            .padding(.top, 20)

            topicBreakdown
                .padding(.top, 22)

            Spacer()

            // Today only: a redo earns nothing, and dropping these leaves room for the back link
            // on this non-scrolling screen.
            if practice == nil {
                streakAndXP
            }

            if displayedQuestions.isEmpty {
                Text("No questions available right now — check back soon.")
                    .font(Theme.Fonts.body(13))
                    .foregroundStyle(Theme.Colors.neutral600)
                    .padding(.top, 12)
            }

            Button(action: { onBegin(displayedLevel) }) {
                Text(beginTitle)
                    .font(Theme.Fonts.heading(17))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .background(Theme.Colors.accent)
            .foregroundStyle(Theme.Colors.bg)
            .padding(.top, 30)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(displayedQuestions.isEmpty)
        }
        .padding(24)
        .background(Theme.Colors.bg)
    }

    private var streakAndXP: some View {
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
    }

    private var displayedLevel: SkillLevel {
        if let selectedLevel { return selectedLevel }
        guard let practice else { return questionRepo.effectiveLevel }
        let levels = practice.levels
        return levels.contains(questionRepo.effectiveLevel) ? questionRepo.effectiveLevel : (levels.first ?? questionRepo.effectiveLevel)
    }

    private var displayedQuestions: [Question] {
        practice?.questions(for: displayedLevel) ?? questionRepo.questions(for: displayedLevel)
    }

    private var showsGradeSwitcher: Bool { practice?.hasDifficultyChoice ?? true }
    private var switcherLevels: [SkillLevel] { practice?.levels ?? SkillLevel.allCases }

    private var dateLabel: String {
        practice.map { DailyEdition.dateLabel(forKey: $0.dateKey) } ?? DailyEdition.dateLabel()
    }

    private var beginTitle: String {
        guard let practice else { return "Begin today's five" }
        return practice.isToday ? "Redo today's five" : "Redo \(DailyEdition.weekdayName(for: practice.dateKey))'s five"
    }

    private var gradeSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(switcherLevels) { level in
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
        // A practice pick is just for this redo — it mustn't change tomorrow's real quiz.
        guard practice == nil, let uid = authRepo.currentUser?.uid else { return }
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
        (practice == nil ? questionRepo.editionNumber : practice?.edition).map { "Edition \($0)" } ?? "Edition —"
    }
}

#Preview {
    DailyQuizEntryView(onBegin: { _ in })
        .environment(ProfileRepository.preview())
        .environment(QuestionRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
