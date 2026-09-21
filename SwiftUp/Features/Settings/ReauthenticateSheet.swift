import SwiftUI
import AuthenticationServices

/// Presented from `SettingsView` when `AuthRepository.deleteAccount()` returns
/// `.requiresRecentSignIn` and the account's provider needs an explicit user action to
/// reauthenticate — a password, or a fresh Sign in with Apple tap. Google needs neither: its SDK
/// presents its own sign-in sheet directly, so `SettingsView` never routes a Google account
/// through this view at all.
struct ReauthenticateSheet: View {
    enum Method: Identifiable {
        case password(email: String)
        case apple

        var id: String {
            switch self {
            case .password: "password"
            case .apple: "apple"
            }
        }
    }

    let method: Method
    let isSubmitting: Bool
    let onSubmitPassword: (String) -> Void
    let onAppleResult: (Result<ASAuthorization, Error>, String) -> Void

    @State private var password = ""
    @State private var currentNonce = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 0)

            Rectangle().fill(Theme.Colors.text).frame(height: 3)

            Text("Confirm it's you").font(Theme.Fonts.heading(24)).padding(.top, 8)
            Text("Deleting your account needs a fresh sign-in, for your security.")
                .font(Theme.Fonts.body(15))
                .foregroundStyle(Theme.Colors.neutral800)

            switch method {
            case .password(let email):
                Text(email).font(.system(size: 13)).foregroundStyle(Theme.Colors.neutral700)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))

                Button(action: { onSubmitPassword(password) }) {
                    Text(isSubmitting ? "Please wait…" : "Confirm and delete")
                        .font(Theme.Fonts.heading(17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
                .disabled(isSubmitting || password.isEmpty)

            case .apple:
                SignInWithAppleButton(.continue) { request in
                    let nonce = AuthRepository.randomNonceString()
                    currentNonce = nonce
                    request.requestedScopes = [.email, .fullName]
                    request.nonce = AuthRepository.sha256(nonce)
                } onCompletion: { result in
                    onAppleResult(result, currentNonce)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 54)
                .disabled(isSubmitting)
            }

            Button("Cancel") { dismiss() }
                .font(.system(size: 15))
                .foregroundStyle(Theme.Colors.accent700)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .background(Theme.Colors.bg)
    }
}

#Preview("Password") {
    ReauthenticateSheet(method: .password(email: "maya@example.com"), isSubmitting: false, onSubmitPassword: { _ in }, onAppleResult: { _, _ in })
}

#Preview("Apple") {
    ReauthenticateSheet(method: .apple, isSubmitting: false, onSubmitPassword: { _ in }, onAppleResult: { _, _ in })
}
