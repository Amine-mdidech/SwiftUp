import SwiftUI

struct DailyQuizEntryView: View {
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(QuestionRepository.self) private var questionRepo
    let onBegin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RuledMasthead(left: "Monday, September 7", right: "Edition 128")

            VStack(alignment: .leading, spacing: 12) {
                EyebrowLabel("The daily five", color: Theme.Colors.accent700)
                Text(topicsHeadline)
                    .font(Theme.Fonts.heading(40))
                Text("Five questions, drawn this morning. About three minutes.")
                    .font(Theme.Fonts.body(16))
                    .foregroundStyle(Theme.Colors.neutral700)
            }
            .padding(.top, 40)

            Spacer()

            HStack(alignment: .bottom, spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    EyebrowLabel("Streak")
                    PlateNumeral("\(profileRepo.profile.streakDays)", font: Theme.Fonts.heading(64))
                    Text("days · \(profileRepo.profile.freezesAvailable) freeze held")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.neutral600)
                }
                VStack(alignment: .leading, spacing: 10) {
                    EyebrowLabel("Level \(profileRepo.profile.level)")
                    Text(profileRepo.profile.levelTitle).font(Theme.Fonts.heading(18))
                    ThinProgressBar(fraction: profileRepo.profile.levelProgressFraction)
                        .frame(width: 118)
                    Text("\(profileRepo.profile.xp) xp · \(profileRepo.profile.xpToNextLevel) to L\(profileRepo.profile.level + 1)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.Colors.neutral600)
                }
            }

            Button(action: onBegin) {
                Text("Begin today's five")
                    .font(Theme.Fonts.heading(17))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .background(Theme.Colors.accent)
            .foregroundStyle(Theme.Colors.bg)
            .padding(.top, 30)
        }
        .padding(24)
        .background(Theme.Colors.bg)
    }

    private var topicsHeadline: String {
        let topics = Array(Set(questionRepo.todayQuestions.map(\.topic))).sorted()
        return topics.joined(separator: ",\n") + "."
    }
}

#Preview {
    DailyQuizEntryView(onBegin: {})
        .environment(ProfileRepository())
        .environment(QuestionRepository.preview())
}
