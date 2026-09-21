import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @State private var difficulty = "Adaptive"
    @State private var cacheOffline = true
    @State private var showOnLeaderboards = true
    @State private var shareStats = false
    // `@State`, not constructed inline in the NavigationLink closure below: that closure isn't
    // guaranteed to run only once, and a fresh `AdMobRewardedAdPresenter()` each time would never
    // have had time to preload an ad before the user taps "Watch one now" (see MainTabView's
    // `adPresenter` for the same fix applied to the practice-redo flow).
    @State private var adPresenter = AdMobRewardedAdPresenter()
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountAlert: DeleteAccountAlert?
    @State private var reauthPrompt: ReauthenticateSheet.Method?
    @Environment(AuthRepository.self) private var authRepository
    @Environment(QuestionRepository.self) private var questionRepository

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings").font(Theme.Fonts.heading(30))

                EyebrowLabel("Account").padding(.top, 24)
                VStack(spacing: 0) {
                    RuledRow(minHeight: 46) {
                        Text("Signed in as").font(Theme.Fonts.body(15))
                        Spacer()
                        Text(authRepository.currentUser?.email ?? authRepository.currentUser?.displayName ?? "—")
                            .font(.system(size: 13.5)).foregroundStyle(Theme.Colors.neutral700)
                    }
                    RuledRow(showBottomRule: true, minHeight: 46) {
                        Text("Support SwiftUp").font(Theme.Fonts.body(15))
                        Spacer()
                        NavigationLink("Donate →") { SupportView(adPresenter: adPresenter) }
                            .font(.system(size: 13.5)).foregroundStyle(Theme.Colors.accent700)
                    }
                }
                .padding(.top, 8)

                EyebrowLabel("Daily quiz").padding(.top, 22)
                VStack(spacing: 0) {
                    RuledRow(minHeight: 46) {
                        Text("Reminder").font(Theme.Fonts.body(15))
                        Spacer()
                        Text("07:30 →").font(.system(size: 14)).foregroundStyle(Theme.Colors.accent700)
                    }
                    RuledRow(showBottomRule: true, minHeight: 46) {
                        Text("Cache for offline").font(Theme.Fonts.body(15))
                        Spacer()
                        SquareToggle(isOn: $cacheOffline)
                    }
                }
                .padding(.top, 8)

                EyebrowLabel("Difficulty").padding(.top, 22)
                SegmentedPicker(
                    options: ["Adaptive", "Junior", "Mid", "Senior"],
                    selection: Binding(
                        get: { difficulty },
                        set: { newValue in
                            difficulty = newValue
                            guard let uid = authRepository.currentUser?.uid else { return }
                            let level = SkillLevel(rawValue: newValue)
                            Task { await questionRepository.setLevelOverride(level, for: uid) }
                        }
                    )
                )
                    .padding(.top, 10)
                Text("Adaptive uses the level you set at onboarding. Junior/Mid/Senior overrides it for tomorrow's five.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 8)

                EyebrowLabel("Privacy & appearance").padding(.top, 22)
                VStack(spacing: 0) {
                    RuledRow(minHeight: 46) {
                        Text("Show me on leaderboards").font(Theme.Fonts.body(15))
                        Spacer()
                        SquareToggle(isOn: $showOnLeaderboards)
                    }
                    RuledRow(minHeight: 46) {
                        Text("Share stats with friends").font(Theme.Fonts.body(15))
                        Spacer()
                        SquareToggle(isOn: $shareStats)
                    }
                    RuledRow(showBottomRule: true, minHeight: 46) {
                        Text("Appearance").font(Theme.Fonts.body(15))
                        Spacer()
                        Text("System →").font(.system(size: 13.5)).foregroundStyle(Theme.Colors.neutral700)
                    }
                }
                .padding(.top, 8)

                HStack(spacing: 18) {
                    Button("Sign out") { authRepository.signOut() }
                        .font(.system(size: 14)).foregroundStyle(Theme.Colors.accent700)
                    Button("Delete account") { showDeleteConfirmation = true }
                        .font(.system(size: 14)).foregroundStyle(Theme.Colors.accent2800)
                        .disabled(isDeletingAccount)
                }
                .padding(.top, 20)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
        .onAppear {
            difficulty = questionRepository.levelOverride?.rawValue ?? "Adaptive"
        }
        .task { await adPresenter.preload() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Notifications") { NotificationSettingsView() }
            }
        }
        .alert("Delete your account?", isPresented: $showDeleteConfirmation) {
            Button("Delete account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and everything in it — xp, streaks, achievements. This can't be undone.")
        }
        .alert(item: $deleteAccountAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .sheet(item: $reauthPrompt) { method in
            ReauthenticateSheet(
                method: method,
                isSubmitting: isDeletingAccount,
                onSubmitPassword: { password in
                    isDeletingAccount = true
                    Task {
                        let result = await authRepository.reauthenticateWithPasswordAndDeleteAccount(password: password)
                        isDeletingAccount = false
                        reauthPrompt = nil
                        await handleDeleteResult(result)
                    }
                },
                onAppleResult: { result, nonce in
                    reauthPrompt = nil
                    isDeletingAccount = true
                    Task {
                        let deleteResult = await authRepository.reauthenticateWithAppleAndDeleteAccount(result: result, rawNonce: nonce)
                        isDeletingAccount = false
                        await handleDeleteResult(deleteResult)
                    }
                }
            )
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        Task {
            let result = await authRepository.deleteAccount()
            isDeletingAccount = false
            await handleDeleteResult(result)
        }
    }

    /// Shared by the initial delete attempt and every reauthentication path below — a passing
    /// reauth always retries the delete itself (see each `AuthRepository.reauthenticateWith...`
    /// method), so `.requiresRecentSignIn` should never recur here in practice; the switch still
    /// handles it defensively rather than assuming that.
    private func handleDeleteResult(_ result: AuthRepository.DeleteAccountResult) async {
        switch result {
        case .deleted:
            break // authRepository's own auth-state listener drives RootView back to signed-out.
        case .requiresRecentSignIn:
            switch authRepository.reauthMethod {
            case .password:
                reauthPrompt = .password(email: authRepository.currentUser?.email ?? "")
            case .apple:
                reauthPrompt = .apple
            case .google:
                isDeletingAccount = true
                let retried = await authRepository.reauthenticateWithGoogleAndDeleteAccount()
                isDeletingAccount = false
                await handleDeleteResult(retried)
            case nil:
                deleteAccountAlert = .failed("Please sign in again, then try deleting your account from here.")
            }
        case .failed:
            deleteAccountAlert = .failed(authRepository.errorMessage ?? "Something went wrong. Please try again.")
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
        .environment(QuestionRepository.preview())
}
