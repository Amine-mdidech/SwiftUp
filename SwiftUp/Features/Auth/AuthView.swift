import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(AuthRepository.self) private var authRepository

    @State private var showEmailFields = false
    @State private var email = ""
    @State private var password = ""
    @State private var currentNonce = ""
    @State private var isSubmitting = false
    @State private var validationMessage: String?
    // `@State`, not constructed inline in the NavigationLink closure below — see SettingsView's
    // `adPresenter` for why (same fix, same reason).
    @State private var adPresenter = AdMobRewardedAdPresenter()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: "SwiftUp", right: "Sign in")

                VStack(alignment: .leading, spacing: 16) {
                    Text("Track your\nprogress.")
                        .font(Theme.Fonts.heading(44))
                        .lineSpacing(-2)
                    Text("Your streak, xp and standing follow you to any device. Answers stay on the device until you join a leaderboard.")
                        .font(Theme.Fonts.body(16))
                        .foregroundStyle(Theme.Colors.neutral800)
                }
                .padding(.top, 38)

                VStack(spacing: 11) {
                    SignInWithAppleButton(.continue) { request in
                        let nonce = AuthRepository.randomNonceString()
                        currentNonce = nonce
                        request.requestedScopes = [.email, .fullName]
                        request.nonce = AuthRepository.sha256(nonce)
                    } onCompletion: { result in
                        Task { await authRepository.handleAppleSignIn(result: result, rawNonce: currentNonce) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 54)

                    Button {
                        Task { await authRepository.signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            GoogleLogo()
                            Text("Continue with Google")
                                .font(Theme.Fonts.body(17))
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))
                    .foregroundStyle(Theme.Colors.text)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showEmailFields = true }
                    } label: {
                        Text("Continue with email")
                            .font(Theme.Fonts.body(17))
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))
                    .foregroundStyle(Theme.Colors.text)
                    .opacity(showEmailFields ? 0.4 : 1)
                    .disabled(showEmailFields)
                }
                .padding(.top, 34)

                if showEmailFields {
                    emailFields
                }

                Text("New here? Any of these creates your account — there is no separate sign-up.")
                    .font(Theme.Fonts.body(13))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(Theme.Colors.text).frame(height: 1)
                    VStack(alignment: .leading, spacing: 10) {
                        EyebrowLabel("Our promise")
                        Text("No subscription. No unwanted ads. Nothing to cancel.")
                            .font(Theme.Fonts.heading(22))
                        Text("Everything is free. Support us only if you want to.")
                            .font(Theme.Fonts.body(13.5))
                            .foregroundStyle(Theme.Colors.neutral800)
                    }
                    .padding(.top, 16)
                }
                .padding(.top, 32)

                NavigationLink {
                    SupportView(adPresenter: adPresenter)
                } label: {
                    VStack(spacing: 14) {
                        Rectangle().fill(Theme.Colors.divider).frame(height: 1)
                        Text("No subscription and no unwanted ads — read the promise.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.Colors.neutral800)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 22)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }

    private var emailFields: some View {
        VStack(spacing: 10) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))

            SecureField("Password", text: $password)
                .textContentType(.password)
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))

            if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Colors.accent2800)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let errorMessage = authRepository.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Colors.accent2800)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: submit) {
                Text(isSubmitting ? "Please wait…" : "Continue")
                    .font(Theme.Fonts.heading(16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .background(Theme.Colors.accent)
            .foregroundStyle(Theme.Colors.bg)
            .disabled(isSubmitting)
        }
        .padding(.top, 14)
    }

    private func submit() {
        validationMessage = nil
        authRepository.errorMessage = nil
        guard AuthValidation.isValidEmail(email) else {
            validationMessage = "Enter a valid email address."
            return
        }
        guard AuthValidation.isValidPassword(password) else {
            validationMessage = "Password must be at least 6 characters."
            return
        }
        isSubmitting = true
        Task {
            await authRepository.continueWithEmail(email: email, password: password)
            isSubmitting = false
        }
    }
}

#Preview {
    NavigationStack {
        AuthView()
            .environment(AuthRepository(isPreview: true))
    }
}
