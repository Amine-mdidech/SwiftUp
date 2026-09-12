import SwiftUI

struct StreakCalendarGrid: View {
    /// Exactly 112 entries, oldest first, today last — `ProfileRepository.streakCalendarDays`.
    let days: [StreakDayState]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<16, id: \.self) { week in
                    VStack(alignment: .center, spacing: 3) {
                        ForEach(0..<7, id: \.self) { day in
                            let index = week * 7 + day
                            Rectangle()
                                .fill(index < days.count ? color(for: days[index]) : Theme.Colors.neutral200)
                                .frame(height: 11)
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                legendItem("done", color: Theme.Colors.text)
                legendItem("freeze", color: Theme.Colors.accent)
                legendItem("missed", color: Theme.Colors.neutral200)
            }
        }
    }

    private func color(for state: StreakDayState) -> Color {
        switch state {
        case .done: Theme.Colors.text
        case .freeze: Theme.Colors.accent
        case .missed: Theme.Colors.neutral200
        }
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            EyebrowLabel(label)
        }
    }
}

#Preview {
    StreakCalendarGrid(days: (0..<112).map { i in
        if i % 23 == 0 { .freeze } else if i % 5 == 0 { .missed } else { .done }
    })
    .padding()
    .background(Theme.Colors.bg)
}
