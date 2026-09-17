import SwiftUI

struct SupportView: View {
    var adPresenter: RewardedAdPresenting = NoOpAdPresenter()

    private let promises = [
        "No subscription. Everything is free, and stays free.",
        "No unwanted ads. Nothing plays unless you start it.",
        "No trial that quietly becomes a bill.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: "Our promise", right: "Standing notice")

                Text("We won't\nsurprise you.")
                    .font(Theme.Fonts.heading(34))
                    .padding(.top, 22)

                VStack(spacing: 0) {
                    ForEach(Array(promises.enumerated()), id: \.offset) { index, text in
                        RuledRow(showBottomRule: index == promises.count - 1, minHeight: 40, alignment: .top) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.accent700)
                            Text(text).font(Theme.Fonts.body(15.5))
                        }
                    }
                }
                .padding(.top, 22)

                donationBlock(
                    title: "Donate", tag: "One-off or monthly",
                    detail: "Any amount, cancel-free. It pays for running the app and writing new questions.",
                    buttonTitle: "Make a donation", primary: true
                )
                .padding(.top, 22)

                donationBlock(
                    title: "Watch an ad, at will", tag: "30 seconds",
                    detail: "Start one whenever you feel like helping out. Never shown unprompted.",
                    buttonTitle: "Watch one now", primary: false,
                    action: {
                        print("[AdPresenter] WATCH BUTTON TAPPED")
                        adPresenter.presentAd { earned in
                            print("[AdPresenter] presentAd completion fired, earned=\(earned)")
                        }
                    }
                )
                .padding(.top, 20)

                Text("Neither one unlocks anything. You already have all of it.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.Colors.neutral700)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }

    @ViewBuilder
    private func donationBlock(title: String, tag: String, detail: String, buttonTitle: String, primary: Bool, action: @escaping () -> Void = {}) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(Theme.Fonts.heading(19))
                Spacer()
                EyebrowLabel(tag)
            }
            Text(detail).font(Theme.Fonts.body(13.5)).foregroundStyle(Theme.Colors.neutral700)
            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .background(primary ? Theme.Colors.accent : Color.clear)
            .foregroundStyle(primary ? Theme.Colors.bg : Theme.Colors.text)
            .overlay(primary ? nil : RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))
            .contentShape(Rectangle())
            .padding(.top, 5)
        }
        .padding(.top, 16)
        .overlay(Rectangle().fill(Theme.Colors.divider), alignment: .top)
    }
}

#Preview {
    SupportView()
}
