import SwiftUI

struct EyebrowLabel: View {
    let text: String
    var color: Color = Theme.Colors.neutral700

    init(_ text: String, color: Color = Theme.Colors.neutral700) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .regular))
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

struct RuledMasthead: View {
    let left: String
    let right: String

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.Colors.text).frame(height: 3)
            HStack {
                EyebrowLabel(left)
                Spacer()
                EyebrowLabel(right)
            }
            .padding(.vertical, 7)
            Rectangle().fill(Theme.Colors.text).frame(height: 1)
        }
    }
}

struct RuledRow<Content: View>: View {
    var showTopRule: Bool = true
    var showBottomRule: Bool = false
    var minHeight: CGFloat = 46
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if showTopRule {
                Rectangle().fill(Theme.Colors.divider).frame(height: 1)
            }
            HStack(spacing: 12) { content() }
                .frame(minHeight: minHeight)
            if showBottomRule {
                Rectangle().fill(Theme.Colors.divider).frame(height: 1)
            }
        }
    }
}

struct ThinProgressBar: View {
    let fraction: Double
    var trackColor: Color = Theme.Colors.neutral200
    var fillColor: Color = Theme.Colors.accent
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(trackColor)
                Rectangle()
                    .fill(fillColor)
                    .frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: height)
    }
}

#Preview("Atoms") {
    VStack(alignment: .leading, spacing: 20) {
        RuledMasthead(left: "SwiftUp", right: "No. 1")
        RuledRow { Text("Reminder"); Spacer(); Text("07:30") }
        ThinProgressBar(fraction: 0.7)
    }
    .padding()
    .background(Theme.Colors.bg)
}
