import SwiftUI

struct SegmentedPicker: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Text(option)
                    .font(.system(size: 13))
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(selection == option ? Theme.Colors.accent : Color.clear)
                    .foregroundStyle(selection == option ? Theme.Colors.bg : Theme.Colors.text)
                    .overlay(alignment: .leading) {
                        if option != options.first {
                            Rectangle().fill(Theme.Colors.divider).frame(width: 1)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option }
                    .accessibilityAddTraits(selection == option ? [.isButton, .isSelected] : .isButton)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct SquareToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isOn ? Theme.Colors.accent : Theme.Colors.neutral300)
            .frame(width: 46, height: 26)
            .overlay(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.Colors.bg)
                    .frame(width: 20, height: 20)
                    .padding(3)
            }
            .frame(width: 46, height: 44)
            .contentShape(Rectangle())
            .onTapGesture { isOn.toggle() }
            .animation(.easeInOut(duration: 0.15), value: isOn)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Toggle")
            .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Recreates the canvas's `.cmyk-num` misregistered-plate numeral: three
/// color copies offset a few points apart, multiply-blended so their
/// overlap reads as dark ink with colored fringes at the edges.
struct PlateNumeral: View {
    let value: String
    var font: Font

    init(_ value: String, font: Font) {
        self.value = value
        self.font = font
    }

    var body: some View {
        ZStack {
            Text(value).font(font).foregroundStyle(Theme.Colors.accent)
                .blendMode(.multiply).offset(x: -1.2, y: 0.4)
            Text(value).font(font).foregroundStyle(Theme.Colors.accent2)
                .blendMode(.multiply).offset(x: 1.2, y: 0.8)
            Text(value).font(font).foregroundStyle(Theme.Colors.processYellow)
                .blendMode(.multiply).offset(x: -0.8, y: -0.7)
        }
        .accessibilityLabel(Text(value))
    }
}

#Preview("Interactive atoms") {
    VStack(spacing: 24) {
        SegmentedPicker(options: ["All", "Junior", "Mid", "Senior"], selection: .constant("Mid"))
        SquareToggle(isOn: .constant(true))
        PlateNumeral("42", font: Theme.Fonts.heading(76, weight: .semibold))
    }
    .padding()
    .background(Theme.Colors.bg)
}
