import SwiftUI

/// Shown after `QuizSummaryView`'s "Done"/"Review misses" — the landing page for the rest of the
/// day. Two ways back into a quiz from here: picking one of the last 7 days — today included — to
/// redo it at the grade already sat, or "Replay today at another difficulty" to reopen the entry
/// screen's grade switcher and sit today's shared quiz again at a *different* grade (see
/// `TodayFlowView`'s `Stage` doc comment). Either way it's a redo, and never touches XP, accuracy,
/// or streak (see `QuizSession.isPractice`'s doc comment for why that's structurally true, not just
/// a convention followed here).
struct QuizEditionsView: View {
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(QuestionRepository.self) private var questionRepo
    let todayXPEarned: Int
    let onSelectDay: (String) -> Void
    let onReplayAtAnotherDifficulty: () -> Void
    @State private var selectedDate: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: "\(editionLabel) · filed", right: DailyEdition.dateLabel())

                VStack(alignment: .leading, spacing: 12) {
                    EyebrowLabel("Today", color: Theme.Colors.accent700)
                    Text("That's today put to bed.")
                        .font(Theme.Fonts.heading(34))
                }
                .padding(.top, 30)

                HStack(alignment: .bottom, spacing: 30) {
                    VStack(alignment: .leading, spacing: 10) {
                        EyebrowLabel("Streak")
                        PlateNumeral("\(profileRepo.profile.streakDays)", font: Theme.Fonts.heading(64))
                        Text("days running")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.neutral600)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        EyebrowLabel("Earned")
                        Text("+\(todayXPEarned) xp today")
                            .font(Theme.Fonts.heading(22))
                            .foregroundStyle(Theme.Colors.accent700)
                    }
                }
                .padding(.top, 26)

                Text("Want more reps? Redo any day from the last week — today included — for practice, it's just for you.")
                    .font(Theme.Fonts.body(15))
                    .foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 24)

                HStack {
                    EyebrowLabel("Back editions")
                    Spacer()
                    EyebrowLabel("\(openCount) open")
                }
                .padding(.top, 30)

                HStack(spacing: 8) {
                    ForEach(Array(profileRepo.lastSevenDays.enumerated()), id: \.offset) { index, entry in
                        dayBlock(entry, isToday: index == profileRepo.lastSevenDays.count - 1)
                    }
                }
                .padding(.top, 12)

                HStack(spacing: 14) {
                    legendItem("sat", color: Theme.Colors.text)
                    legendItem("open to sit", color: Theme.Colors.neutral200)
                    legendItem("today", color: Theme.Colors.accent)
                }
                .padding(.top, 14)

                if let oldest = profileRepo.lastSevenDays.first {
                    Text("\(DailyEdition.weekdayName(for: oldest.date)) closes tonight.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.neutral600)
                        .padding(.top, 12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    EyebrowLabel("What a redo is worth")
                    Text("0 xp · doesn't count toward accuracy · doesn't repair your streak")
                        .font(Theme.Fonts.body(14))
                        .foregroundStyle(Theme.Colors.neutral700)
                }
                .padding(.top, 26)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .background(Theme.Colors.bg)
        // Pinned below the scrollable content instead of laid out inline with it: with seven day
        // blocks, the legend, and both worth-of-a-redo sections above it, an inline "Sit Monday's"
        // button routinely fell below the fold on anything shorter than a Pro Max, so reaching it
        // meant scrolling past everything else first. Pinning removes that scroll entirely.
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
    }

    /// One button at a time, not both stacked: with today selected (or nothing selected yet —
    /// today is this screen's default focus), the two read as the same offer twice ("redo today"
    /// and "replay today at another difficulty" are barely distinguishable sitting on top of each
    /// other), so only the more capable one — the grade switcher — shows. Selecting a *different*
    /// day swaps to that day's own plain redo, which the switcher can't do (it only ever replays
    /// today's shared quiz).
    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 12) {
            if isTodaySelected {
                Button(action: onReplayAtAnotherDifficulty) {
                    Text("↻ Replay today at another difficulty")
                        .font(.system(size: 15.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .foregroundStyle(Theme.Colors.accent700)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.accent, lineWidth: 1))
            } else if let selectedDate {
                Button(action: { onSelectDay(selectedDate) }) {
                    Text("\(actionVerb(for: selectedDate)) \(DailyEdition.weekdayName(for: selectedDate))'s")
                        .font(.system(size: 16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(Theme.Colors.bg)
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
    }

    private var isTodaySelected: Bool {
        selectedDate == nil || selectedDate == DailyEdition.todayKey()
    }

    private var editionLabel: String {
        questionRepo.editionNumber.map { "Edition \($0)" } ?? "Edition —"
    }

    /// Days in the window not yet sat — informational only (still shown even though every day,
    /// sat or not, is now tappable to redo).
    private var openCount: Int {
        let days = profileRepo.lastSevenDays
        guard days.count > 1 else { return 0 }
        return days.dropLast().filter { $0.state == .missed }.count
    }

    /// "Sit" for a day never completed, "Redo" for one already sat (`.done`/`.freeze`) — including
    /// today, whose state is already `.done` by the time this screen renders.
    private func actionVerb(for date: String) -> String {
        profileRepo.lastSevenDays.first(where: { $0.date == date })?.state == .missed ? "Sit" : "Redo"
    }

    @ViewBuilder
    private func dayBlock(_ entry: (date: String, state: StreakDayState), isToday: Bool) -> some View {
        let isSelected = selectedDate == entry.date
        let isMissed = entry.state == .missed
        let fill: Color = isToday ? Theme.Colors.accent : (isMissed ? Theme.Colors.neutral200 : Theme.Colors.text)
        let foreground: Color = (isToday || !isMissed) ? Theme.Colors.bg : Theme.Colors.text

        VStack(spacing: 6) {
            Text(DailyEdition.shortWeekdayName(for: entry.date))
                .font(.system(size: 11, weight: .semibold))
            Text(isToday ? "today" : (isMissed ? "open to sit" : "sat"))
                .font(.system(size: 9))
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .foregroundStyle(foreground)
        .background(fill)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(isSelected ? Theme.Colors.accent700 : Theme.Colors.divider, lineWidth: isSelected ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDate = isSelected ? nil : entry.date
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            EyebrowLabel(label)
        }
    }
}

#Preview {
    QuizEditionsView(todayXPEarned: 95, onSelectDay: { _ in }, onReplayAtAnotherDifficulty: {})
        .environment(ProfileRepository.preview())
        .environment(QuestionRepository.preview())
}
