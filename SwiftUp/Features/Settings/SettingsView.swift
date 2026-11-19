import SwiftUI

/// Design 4a: account, notifications, and privacy on one ruled index (the separate notifications
/// screen is folded in here). The notification switches are read back by `MainTabView`, which
/// re-plans the pending local notifications through `ReminderScheduler` whenever one changes.
struct SettingsView: View {
    @AppStorage(NotificationPreferences.Keys.dailyReminder) private var dailyReminderOn = true
    @AppStorage(NotificationPreferences.Keys.streakAtRisk) private var streakAtRiskOn = true
    @AppStorage(NotificationPreferences.Keys.weeklyEdition) private var weeklyEditionOn = true
    @AppStorage(NotificationPreferences.Keys.quietHours) private var quietHoursOn = true
    @AppStorage("settings.privacy.shareGradeAndStreak") private var shareGradeAndStreak = true
    // `@State`, not constructed inline in the NavigationLink closure below: that closure isn't
    // guaranteed to run only once, and a fresh `AdMobRewardedAdPresenter()` each time would never
    // have had time to preload an ad before the user taps "Watch one now" (see MainTabView's
    // `adPresenter` for the same fix applied to the practice-redo flow).
    @State private var adPresenter = AdMobRewardedAdPresenter()
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var notificationsDenied = false
    @State private var deleteAccountAlert: DeleteAccountAlert?
    @Environment(AuthRepository.self) private var authRepository
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button("← Profile") { dismiss() }
                    .font(Theme.Fonts.body(15))
                    .foregroundStyle(Theme.Colors.accent700)
                    .frame(minHeight: 44)

                Text("Settings").font(Theme.Fonts.heading(32)).padding(.top, 10)

                EyebrowLabel("Account").padding(.top, 26)
                VStack(spacing: 0) {
                    RuledRow(minHeight: 46) {
                        Text(signedInLabel).font(Theme.Fonts.body(15))
                        Spacer()
                        Text(authRepository.currentUser?.email ?? authRepository.currentUser?.displayName ?? "—")
                            .font(Theme.Fonts.body(13.5)).foregroundStyle(Theme.Colors.neutral700)
                    }
                    RuledRow(showBottomRule: true, minHeight: 46) {
                        Text("Support SwiftUp").font(Theme.Fonts.body(15))
                        Spacer()
                        NavigationLink("Donate →") { SupportView(adPresenter: adPresenter) }
                            .font(Theme.Fonts.body(13.5)).foregroundStyle(Theme.Colors.accent700)
                    }
                }
                .padding(.top, 10)

                EyebrowLabel("Notifications").padding(.top, 24)
                VStack(spacing: 0) {
                    toggleRow("Daily quiz reminder", detail: "07:30", isOn: $dailyReminderOn)
                    toggleRow("Streak at risk", detail: "21:00", isOn: $streakAtRiskOn)
                    toggleRow("Weekly edition", detail: "Sun", isOn: $weeklyEditionOn)
                    toggleRow("Quiet hours", detail: "22:00–07:00", isOn: $quietHoursOn, isLast: true)
                }
                .padding(.top, 10)
                if notificationsDenied {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Notifications are off for SwiftUp in iOS Settings.")
                            .font(Theme.Fonts.body(12.5)).foregroundStyle(Theme.Colors.neutral700)
                        Spacer()
                        Button("Open →") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(Theme.Fonts.body(13.5)).foregroundStyle(Theme.Colors.accent700)
                    }
                    .padding(.top, 8)
                }

                EyebrowLabel("Privacy").padding(.top, 24)
                VStack(spacing: 0) {
                    toggleRow("Share my grade and streak", isOn: $shareGradeAndStreak, isLast: true)
                }
                .padding(.top, 10)

                HStack(spacing: 18) {
                    Button("Sign out") { authRepository.signOut() }
                        .font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.accent700)
                    Button("Delete account") { showDeleteConfirmation = true }
                        .font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.accent2800)
                        .disabled(isDeletingAccount)
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Theme.Colors.bg)
        .navigationBarBackButtonHidden()
        .task { await adPresenter.preload() }
        // Keyed on scene phase so the hint clears on return from iOS Settings.
        .task(id: scenePhase) { notificationsDenied = await ReminderScheduler.authorizationStatus() == .denied }
        .alert("Delete your account?", isPresented: $showDeleteConfirmation) {
            Button("Delete account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and everything in it — xp, streaks, achievements. This can't be undone.")
        }
        .alert(item: $deleteAccountAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }

    private var signedInLabel: String {
        authRepository.currentUser?.signInMethod.map { "Signed in with \($0)" } ?? "Signed in as"
    }

    private func toggleRow(_ title: String, detail: String? = nil, isOn: Binding<Bool>, isLast: Bool = false) -> some View {
        RuledRow(showBottomRule: isLast, minHeight: 46) {
            Text(title).font(Theme.Fonts.body(15))
            Spacer()
            if let detail {
                Text(detail).font(Theme.Fonts.body(13.5)).foregroundStyle(Theme.Colors.neutral700)
            }
            SquareToggle(isOn: isOn)
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        Task {
            let result = await authRepository.deleteAccount()
            isDeletingAccount = false
            switch result {
            case .deleted:
                break // authRepository's own auth-state listener drives RootView back to signed-out.
            case .failed:
                deleteAccountAlert = .failed(authRepository.errorMessage ?? "Something went wrong. Please try again.")
            }
        }
    }
}

private enum DeleteAccountAlert: Identifiable {
    case failed(String)

    var id: String { "failed" }
    var title: String { "Couldn't delete account" }
    var message: String {
        switch self {
        case .failed(let message): message
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
