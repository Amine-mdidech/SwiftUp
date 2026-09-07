import SwiftUI

enum AppTab: String, CaseIterable {
    case today = "Today"
    case prep = "Prep"
    case ranks = "Ranks"
    case record = "Record"
}

/// Recreates the canvas's shared footer — a hairline rule above four
/// ruled-serif labels — instead of the stock iOS tab bar chrome.
struct CustomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.Colors.divider).frame(height: 1)
            HStack {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue)
                        .font(.system(size: 12.5, weight: selection == tab ? .semibold : .regular))
                        .foregroundStyle(selection == tab ? Theme.Colors.accent700 : Theme.Colors.neutral700)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { selection = tab }
                }
            }
            .padding(.top, 13)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview {
    VStack {
        Spacer()
        CustomTabBar(selection: .constant(.record))
    }
    .background(Theme.Colors.surface)
}
