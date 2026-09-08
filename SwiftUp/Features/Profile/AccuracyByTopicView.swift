import SwiftUI

struct AccuracyByTopicView: View {
    @Environment(ProfileRepository.self) private var repo

    private var sortedTopics: [TopicAccuracy] {
        repo.topics.sorted { $0.accuracyPercent < $1.accuracyPercent }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Accuracy by\ntopic").font(Theme.Fonts.heading(30))
                Text("\(repo.topics.count) topics, \(repo.profile.answeredCount) questions answered. Ranked worst first — the quiz weights your next five toward the bottom of this list.")
                    .font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 12)

                VStack(spacing: 0) {
                    ForEach(sortedTopics) { topic in
                        RuledRow(minHeight: 40) {
                            Text(topic.name).font(Theme.Fonts.body(14.5))
                            Spacer()
                            ThinProgressBar(
                                fraction: Double(topic.accuracyPercent) / 100,
                                fillColor: topic.accuracyPercent < 60 ? Theme.Colors.accent2 : Theme.Colors.accent,
                                height: 8
                            )
                            .frame(width: 130)
                            Text("\(topic.accuracyPercent)").font(Theme.Fonts.heading(14)).frame(width: 34, alignment: .trailing)
                        }
                    }
                }
                .padding(.top, 22)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview {
    NavigationStack { AccuracyByTopicView() }
        .environment(ProfileRepository())
}
