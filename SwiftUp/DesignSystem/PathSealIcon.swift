import SwiftUI

/// The seal mark used throughout the Library: dashed when untouched, a cyan progress ring while
/// in progress, struck in ink and yellow once every class in the path is done.
struct PathSealIcon: View {
    let isSealed: Bool
    let fraction: Double
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            if isSealed {
                Circle().fill(Theme.Colors.text)
                StarShape().fill(Theme.Colors.processYellow).padding(size * 0.24)
            } else if fraction > 0 {
                Circle().stroke(Theme.Colors.neutral200, lineWidth: max(2, size * 0.07))
                Circle().trim(from: 0, to: fraction)
                    .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: max(2, size * 0.07), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                StarShape().stroke(Theme.Colors.accent700, lineWidth: 1.4).padding(size * 0.28)
            } else {
                Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])).foregroundStyle(Theme.Colors.neutral400)
                StarShape().stroke(Theme.Colors.neutral400, lineWidth: 1.4).padding(size * 0.28)
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        PathSealIcon(isSealed: false, fraction: 0)
        PathSealIcon(isSealed: false, fraction: 0.4)
        PathSealIcon(isSealed: true, fraction: 1)
    }
    .padding()
    .background(Theme.Colors.bg)
}
