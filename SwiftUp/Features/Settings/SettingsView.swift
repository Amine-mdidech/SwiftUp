import SwiftUI

struct SettingsView: View {
    @State private var difficulty = "Adaptive"
    @State private var cacheOffline = true
    @State private var showOnLeaderboards = true
    @State private var shareStats = false
    @Environment(AuthRepository.self) private var authRepository

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
                        NavigationLink("Donate →") { SupportView() }
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
                SegmentedPicker(options: ["Adaptive", "Junior", "Mid", "Senior"], selection: $difficulty)
                    .padding(.top, 10)
                Text("Adaptive weights your next five toward topics under 60%.")
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
                    Text("Delete account").font(.system(size: 14)).foregroundStyle(Theme.Colors.accent2800)
                }
                .padding(.top, 20)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Notifications") { NotificationSettingsView() }
            }
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
