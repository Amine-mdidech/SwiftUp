import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .today
    // `@State`, not constructed inline in `body`: `body` re-evaluates on every tab switch (this
    // view's own `selectedTab` is `@State`), and a fresh `AdMobRewardedAdPresenter()` each time
    // would restart its preload cycle and orphan any in-flight ad load every time the user just
    // switched tabs.
    @State private var adPresenter = AdMobRewardedAdPresenter()
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(NotificationPreferences.Keys.dailyReminder) private var dailyReminderOn = true
    @AppStorage(NotificationPreferences.Keys.streakAtRisk) private var streakAtRiskOn = true
    @AppStorage(NotificationPreferences.Keys.weeklyEdition) private var weeklyEditionOn = true
    @AppStorage(NotificationPreferences.Keys.quietHours) private var quietHoursOn = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                TodayFlowView(adPresenter: adPresenter)
                    .opacity(selectedTab == .today ? 1 : 0)
                    .allowsHitTesting(selectedTab == .today)
                NavigationStack { InterviewBankView() }
                    .opacity(selectedTab == .prep ? 1 : 0)
                    .allowsHitTesting(selectedTab == .prep)
                NavigationStack { LibraryView() }
                    .opacity(selectedTab == .library ? 1 : 0)
                    .allowsHitTesting(selectedTab == .library)
                NavigationStack { ProfileHomeView() }
                    .opacity(selectedTab == .record ? 1 : 0)
                    .allowsHitTesting(selectedTab == .record)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            CustomTabBar(selection: $selectedTab)
        }
        .task { await adPresenter.preload() }
        .task(id: reminderInputs) {
            guard scenePhase == .active else { return }
            await ReminderScheduler.refresh(
                preferences: reminderInputs.preferences,
                completedToday: reminderInputs.completedToday,
                streakDays: reminderInputs.streakDays
            )
        }
    }

    /// Everything the pending notifications depend on. Re-planned whenever any of it changes —
    /// a Settings switch, finishing today's quiz, the profile (streak) loading — and on every
    /// return to the foreground, which also catches a new calendar day.
    private var reminderInputs: ReminderInputs {
        let today = DailyEdition.todayKey()
        return ReminderInputs(
            preferences: NotificationPreferences(
                dailyReminder: dailyReminderOn, streakAtRisk: streakAtRiskOn,
                weeklyEdition: weeklyEditionOn, quietHours: quietHoursOn
            ),
            today: today,
            completedToday: profileRepo.streakDayRecords[today] == .done,
            streakDays: profileRepo.profile.streakDays,
            isActive: scenePhase == .active
        )
    }
}

private struct ReminderInputs: Hashable {
    let preferences: NotificationPreferences
    let today: String
    let completedToday: Bool
    let streakDays: Int
    let isActive: Bool
}

#Preview {
    MainTabView()
        .environment(QuestionRepository.preview())
        .environment(ProfileRepository.preview())
        .environment(InterviewRepository.preview())
        .environment(LibraryRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
