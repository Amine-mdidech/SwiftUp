import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RuledMasthead(left: "SwiftUp", right: "No. 1")

            VStack(alignment: .leading, spacing: 22) {
                Text("Five\nquestions\na day.")
                    .font(Theme.Fonts.heading(44))
                    .lineSpacing(-2)
                Text("Swift, SwiftUI, concurrency, ARC. Three minutes each morning, and a bank of interview questions for when it counts.")
                    .font(Theme.Fonts.body(16))
                    .foregroundStyle(Theme.Colors.neutral800)
            }
            .padding(.top, 44)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    PlateNumeral("1,240", font: Theme.Fonts.heading(34))
                    EyebrowLabel("Questions in the bank")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("12").font(Theme.Fonts.heading(34))
                    EyebrowLabel("Topics tagged")
                }
            }
            .padding(.top, 36)

            Spacer()

            VStack(spacing: 10) {
                Button(action: onContinue) {
                    Text("Sign in with Apple")
                        .font(Theme.Fonts.heading(16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)

                Button(action: onContinue) {
                    Text("Use email instead")
                        .font(Theme.Fonts.body(15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))
                .foregroundStyle(Theme.Colors.text)

                Text("Your answers stay on your device unless you join a leaderboard.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Colors.neutral700)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .background(Theme.Colors.bg)
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
