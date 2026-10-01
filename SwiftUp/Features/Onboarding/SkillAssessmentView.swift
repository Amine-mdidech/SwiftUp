import SwiftUI

struct SkillAssessmentView: View {
    @State private var selection: SkillLevel = .mid
    let onContinue: (SkillLevel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Where are you\nright now?")
                .font(Theme.Fonts.heading(30))
            Text("This only sets your first week. The quiz adapts from your actual answers after that.")
                .font(Theme.Fonts.body(14.5))
                .foregroundStyle(Theme.Colors.neutral800)
                .padding(.top, 10)

            VStack(spacing: 0) {
                ForEach(SkillLevel.onboardingChoices) { level in
                    RuledRow(showBottomRule: level == SkillLevel.onboardingChoices.last, minHeight: 60) {
                        Circle()
                            .strokeBorder(selection == level ? Theme.Colors.accent : Theme.Colors.divider, lineWidth: 1.5)
                            .background(Circle().fill(selection == level ? Theme.Colors.accent : Color.clear))
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(level.displayName).font(Theme.Fonts.heading(17))
                            Text(level.blurb).font(Theme.Fonts.body(13)).foregroundStyle(Theme.Colors.neutral700)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, selection == level ? 10 : 0)
                    .background(selection == level ? Theme.Colors.accent100 : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = level }
                }
            }
            .padding(.top, 20)

            Spacer()

            Button {
                onContinue(selection)
            } label: {
                Text("Start day one")
                    .font(Theme.Fonts.heading(17))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .background(Theme.Colors.accent)
            .foregroundStyle(Theme.Colors.bg)
        }
        .padding(24)
        .background(Theme.Colors.bg)
    }
}

#Preview {
    SkillAssessmentView(onContinue: { _ in })
}
