import SwiftUI

enum AppTab: String, CaseIterable {
    case today = "Today"
    case prep = "Prep"
    case ranks = "Ranks"
    case record = "Record"
}

/// Recreates the canvas's shared footer — a hairline rule, four icon+label
/// tabs, and a 3pt accent bar over whichever tab is selected — instead of
/// the stock iOS tab bar chrome.
struct CustomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.Colors.divider).frame(height: 1)
            HStack(spacing: 4) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    tabItem(tab)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .background(Theme.Colors.bg.ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder
    private func tabItem(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        let tint = isSelected ? Theme.Colors.accent700 : Theme.Colors.neutral700

        ZStack(alignment: .top) {
            Rectangle()
                .fill(isSelected ? Theme.Colors.accent700 : .clear)
                .frame(width: 34, height: 3)
            VStack(spacing: 5) {
                TabBarIcon(tab: tab)
                    .frame(width: 18, height: 18)
                Text(tab.rawValue)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
            }
            .padding(.top, 7)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { selection = tab }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Line-art icons traced from the canvas's tab bar SVGs (18×18 units,
/// `currentColor` fills/strokes) — drawn with `Canvas` so `.foreground`
/// picks up whatever tint `CustomTabBar` applies, matching the SVGs'
/// `currentColor` behavior exactly.
private struct TabBarIcon: View {
    let tab: AppTab

    var body: some View {
        switch tab {
        case .today: TodayIcon()
        case .prep: PrepIcon()
        case .ranks: RanksIcon()
        case .record: RecordIcon()
        }
    }
}

private struct TodayIcon: View {
    var body: some View {
        Canvas { context, _ in
            var frame = Path()
            frame.addRect(CGRect(x: 2, y: 3, width: 14, height: 12))
            context.stroke(frame, with: .foreground, lineWidth: 1.5)

            var divider = Path()
            divider.move(to: CGPoint(x: 2, y: 7))
            divider.addLine(to: CGPoint(x: 16, y: 7))
            context.stroke(divider, with: .foreground, lineWidth: 1.5)

            context.opacity = 0.55
            var lines = Path()
            lines.move(to: CGPoint(x: 5, y: 10.5)); lines.addLine(to: CGPoint(x: 10, y: 10.5))
            lines.move(to: CGPoint(x: 5, y: 12.8)); lines.addLine(to: CGPoint(x: 12, y: 12.8))
            context.stroke(lines, with: .foreground, lineWidth: 1.3)
        }
    }
}

private struct PrepIcon: View {
    var body: some View {
        Canvas { context, _ in
            context.opacity = 0.45
            var back = Path()
            back.addRect(CGRect(x: 4.5, y: 2.5, width: 11, height: 11))
            context.stroke(back, with: .foreground, lineWidth: 1.5)

            context.opacity = 1
            var front = Path()
            front.addRect(CGRect(x: 2, y: 5, width: 11, height: 10.5))
            context.stroke(front, with: .foreground, lineWidth: 1.5)
        }
    }
}

private struct RanksIcon: View {
    var body: some View {
        Canvas { context, _ in
            context.opacity = 0.45
            context.fill(Path(CGRect(x: 2, y: 10, width: 3.6, height: 5.5)), with: .foreground)
            context.opacity = 1
            context.fill(Path(CGRect(x: 7.2, y: 6, width: 3.6, height: 9.5)), with: .foreground)
            context.opacity = 0.45
            context.fill(Path(CGRect(x: 12.4, y: 2.5, width: 3.6, height: 13)), with: .foreground)
        }
    }
}

private struct RecordIcon: View {
    var body: some View {
        Canvas { context, _ in
            var ring = Path()
            ring.addEllipse(in: CGRect(x: 2.4, y: 2.4, width: 13.2, height: 13.2))
            context.stroke(ring, with: .foreground, lineWidth: 1.5)

            var dot = Path()
            dot.addEllipse(in: CGRect(x: 6.4, y: 6.4, width: 5.2, height: 5.2))
            context.fill(dot, with: .foreground)

            context.opacity = 0.55
            var ticks = Path()
            ticks.move(to: CGPoint(x: 9, y: 0.8)); ticks.addLine(to: CGPoint(x: 9, y: 3.8))
            ticks.move(to: CGPoint(x: 9, y: 14.2)); ticks.addLine(to: CGPoint(x: 9, y: 17.2))
            ticks.move(to: CGPoint(x: 0.8, y: 9)); ticks.addLine(to: CGPoint(x: 3.8, y: 9))
            ticks.move(to: CGPoint(x: 14.2, y: 9)); ticks.addLine(to: CGPoint(x: 17.2, y: 9))
            context.stroke(ticks, with: .foreground, lineWidth: 1.2)
        }
    }
}

#Preview {
    VStack {
        Spacer()
        CustomTabBar(selection: .constant(.record))
    }
    .background(Theme.Colors.surface)
}
