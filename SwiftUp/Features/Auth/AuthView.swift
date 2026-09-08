import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(AuthRepository.self) private var authRepository

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var currentNonce = ""
    @State private var isSubmitting = false
    @State private var validationMessage: String?

    private enum Mode: String, CaseIterable {
        case signIn = "Sign in"
        case signUp = "Create account"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: "SwiftUp", right: "Sign in")

                VStack(alignment: .leading, spacing: 22) {
                    Text("Track your\nprogress.")
                        .font(Theme.Fonts.heading(38))
                        .lineSpacing(-2)
                    Text("Sign in to save your streak, XP, and rank across devices.")
                        .font(Theme.Fonts.body(16))
                        .foregroundStyle(Theme.Colors.neutral800)
                }
                .padding(.top, 44)

                SignInWithAppleButton(.signIn) { request in
                    let nonce = AuthRepository.randomNonceString()
                    currentNonce = nonce
                    request.requestedScopes = [.email, .fullName]
                    request.nonce = AuthRepository.sha256(nonce)
                } onCompletion: { result in
                    Task { await authRepository.handleAppleSignIn(result: result, rawNonce: currentNonce) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.top, 36)

                HStack(spacing: 12) {
                    Rectangle().fill(Theme.Colors.divider).frame(height: 1)
                    Text("or").font(.system(size: 12)).foregroundStyle(Theme.Colors.neutral700)
                    Rectangle().fill(Theme.Colors.divider).frame(height: 1)
                }
                .padding(.top, 20)

                SegmentedPicker(
                    options: Mode.allCases.map(\.rawValue),
                    selection: Binding(
                        get: { mode.rawValue },
                        set: { newValue in
                            mode = Mode(rawValue: newValue) ?? .signIn
                            authRepository.errorMessage = nil
                        }
                    )
                )
                .padding(.top, 20)

                VStack(spacing: 10) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))

                    SecureField("Password", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .padding(12)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))
                }
                .padding(.top, 16)

                if let validationMessage {
                    Text(validationMessage)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.Colors.accent2800)
                        .padding(.top, 8)
                }
                if let errorMessage = authRepository.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.Colors.accent2800)
                        .padding(.top, 8)
                }

                Button(action: submit) {
                    Text(isSubmitting ? "Please wait…" : mode.rawValue)
                        .font(Theme.Fonts.heading(16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
                .disabled(isSubmitting)
                .padding(.top, 16)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
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
            switch mode {
            case .signIn: await authRepository.signIn(email: email, password: password)
            case .signUp: await authRepository.signUp(email: email, password: password)
            }
            isSubmitting = false
        }
    }
}

#Preview {
    AuthView()
        .environment(AuthRepository(isPreview: true))
}
