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
    /// Vertical alignment of the row's content HStack. Defaults to `.center`, which is wrong for a
    /// short leading marker (a numeral, an arrow) next to text that can wrap to multiple lines — the
    /// marker ends up centered against the whole wrapped block instead of sitting next to its first
    /// line. Pass `.top` for that shape of row.
    var alignment: VerticalAlignment = .center
    @ViewBuilder var content: () -> Content

    var body: some View {
        // `.leading`, not the VStack default `.center`: the divider Rectangles are full-width, but
        // the content HStack only stretches to full width when something inside it (a `Spacer()`)
        // forces that — otherwise it sizes to its own content and gets centered under the dividers
        // instead of left-aligned. Every other call site has a trailing `Spacer()`, so this was
        // invisible until a row (talking points) had none: each row's HStack then centers by a
        // different amount depending on how much its own text wrapped, producing inconsistent left
        // edges from row to row.
        VStack(alignment: .leading, spacing: 0) {
            if showTopRule {
                Rectangle().fill(Theme.Colors.divider).frame(height: 1)
            }
            HStack(alignment: alignment, spacing: 12) { content() }
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
