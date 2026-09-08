import SwiftUI

private struct NotificationRow: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let defaultOn: Bool
}

struct NotificationSettingsView: View {
    private static let rows = [
        NotificationRow(title: "Daily quiz reminder", detail: "Every day at 07:30", defaultOn: true),
        NotificationRow(title: "Streak at risk", detail: "21:00, only when today is unfinished", defaultOn: true),
        NotificationRow(title: "New questions & topics", detail: "When the bank gains a category", defaultOn: false),
        NotificationRow(title: "Weekly edition", detail: "Sunday summary of the week's accuracy", defaultOn: true),
    ]

    @State private var toggles: [Bool] = NotificationSettingsView.rows.map(\.defaultOn)
    @State private var quietHoursOn = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Notifications").font(Theme.Fonts.heading(30))
                Text("Three a day at most.").font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    ForEach(Array(Self.rows.enumerated()), id: \.element.id) { index, row in
                        RuledRow(showBottomRule: index == Self.rows.count - 1, minHeight: 52) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title).font(Theme.Fonts.heading(15.5))
                                Text(row.detail).font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
                            }
                            Spacer()
                            SquareToggle(isOn: $toggles[index])
                        }
                    }
                }
                .padding(.top, 22)

                EyebrowLabel("Quiet hours").padding(.top, 22)
                RuledRow(showBottomRule: true, minHeight: 46) {
                    Text("22:00 — 07:00").font(Theme.Fonts.body(15))
                    Spacer()
                    SquareToggle(isOn: $quietHoursOn)
                }
                .padding(.top, 8)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview {
    NavigationStack { NotificationSettingsView() }
}
