import SwiftUI

struct TopicInterestsView: View {
    static let allTopics = [
        "Swift language", "SwiftUI", "Concurrency", "UIKit", "Memory · ARC",
        "Architecture", "Networking", "Core Data", "Testing", "Xcode", "App lifecycle", "Combine"
    ]

    @State private var selected: Set<String> = ["Swift language", "Concurrency", "Memory · ARC", "Testing"]
    let onFinish: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 9)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Step 2 of 2")
                Spacer()
            }
            .font(.system(size: 10)).foregroundStyle(Theme.Colors.neutral700)

            HStack(spacing: 4) {
                Rectangle().fill(Theme.Colors.text).frame(height: 4)
                Rectangle().fill(Theme.Colors.text).frame(height: 4)
            }
            .padding(.top, 6)

            Text("What should we\nweight toward?")
                .font(Theme.Fonts.heading(30))
                .padding(.top, 24)
            Text("Pick as many as you like. Everything else still appears, just less often.")
                .font(Theme.Fonts.body(14.5))
                .foregroundStyle(Theme.Colors.neutral800)
                .padding(.top, 10)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 9) {
                ForEach(Self.allTopics, id: \.self) { topic in
                    Text(topic)
                        .font(.system(size: 14.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(selected.contains(topic) ? Theme.Colors.accent : Color.clear)
                        .foregroundStyle(selected.contains(topic) ? Theme.Colors.bg : Theme.Colors.text)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(selected.contains(topic) ? Color.clear : Theme.Colors.divider))
                        .onTapGesture { toggle(topic) }
                }
            }
            .padding(.top, 26)

            HStack {
                EyebrowLabel("\(selected.count) selected")
                Spacer()
                Button("Select all") { selected = Set(Self.allTopics) }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.accent700)
            }
            .padding(.top, 22)
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.divider).frame(height: 1) }

            Spacer()

            Button(action: onFinish) {
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

    private func toggle(_ topic: String) {
        if selected.contains(topic) { selected.remove(topic) } else { selected.insert(topic) }
    }
}

#Preview {
    TopicInterestsView(onFinish: {})
}
