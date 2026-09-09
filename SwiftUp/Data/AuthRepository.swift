import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import GoogleSignIn
import CryptoKit

@Observable
@MainActor
final class AuthRepository {
    private(set) var isSignedIn: Bool
    private(set) var currentUser: AuthUser?
    var errorMessage: String?

    private let isPreview: Bool
    // Read in `deinit`, which is nonisolated even for a @MainActor class; this
    // handle is only ever mutated on the main actor (in `init`), and isn't
    // rendered by SwiftUI, so it's excluded from observation tracking.
    @ObservationIgnored
    nonisolated(unsafe) private var authStateHandle: AuthStateDidChangeListenerHandle?

    init(isPreview: Bool = false, signedIn: Bool = false) {
        self.isPreview = isPreview
        self.isSignedIn = isPreview ? signedIn : false
        self.currentUser = (isPreview && signedIn)
            ? AuthUser(uid: "preview-user", email: "preview@example.com", displayName: "Preview User")
            : nil

        guard !isPreview else { return }

        let restored = Auth.auth().currentUser
        self.isSignedIn = restored != nil
        self.currentUser = restored.map { AuthUser(uid: $0.uid, email: $0.email, displayName: $0.displayName) }

        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.isSignedIn = user != nil
            self.currentUser = user.map {
                AuthUser(uid: $0.uid, email: $0.email, displayName: $0.displayName)
            }
        }
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
    }

    // MARK: - Email/password

    /// No separate sign-in/sign-up choice is shown to the user — this tries
    /// signing in first, and silently creates the account on the one error
    /// that means "no such user," so a single button covers both cases.
    func continueWithEmail(email: String, password: String) async {
        guard !isPreview else { return }
        errorMessage = nil
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            guard Self.isUserNotFound(error) else {
                errorMessage = Self.friendlyMessage(for: error)
                return
            }
            do {
                let result = try await Auth.auth().createUser(withEmail: email, password: password)
                await ensureUserDocument(uid: result.user.uid, email: result.user.email, displayName: result.user.displayName)
            } catch {
                errorMessage = Self.friendlyMessage(for: error)
            }
        }
    }

    private static func isUserNotFound(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == AuthErrorDomain && AuthErrorCode(rawValue: nsError.code) == .userNotFound
    }

    // MARK: - Sign in with Google

    func signInWithGoogle() async {
        guard !isPreview else { return }
        errorMessage = nil
        guard let presenter = Self.topViewController() else {
            errorMessage = "Something went wrong. Please try again."
            return
        }
        do {
            let googleResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = googleResult.user.idToken?.tokenString else {
                errorMessage = "Something went wrong. Please try again."
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: googleResult.user.accessToken.tokenString
            )
            let result = try await Auth.auth().signIn(with: credential)
            await ensureUserDocument(uid: result.user.uid, email: result.user.email, displayName: result.user.displayName)
        } catch {
            if (error as? GIDSignInError)?.code == .canceled { return }
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    private static func topViewController() -> UIViewController? {
        guard
            let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    func signOut() {
        guard !isPreview else { return }
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    // MARK: - Sign in with Apple

    func handleAppleSignIn(result: Result<ASAuthorization, Error>, rawNonce: String) async {
        guard !isPreview else { return }
        errorMessage = nil
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "Sign in with Apple failed. Please try again."

        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idTokenString = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Sign in with Apple failed. Please try again."
                return
            }

            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: rawNonce,
                fullName: credential.fullName
            )

            do {
                let result = try await Auth.auth().signIn(with: firebaseCredential)
                let nameFromApple = [credential.fullName?.givenName, credential.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                let displayName = result.user.displayName ?? (nameFromApple.isEmpty ? nil : nameFromApple)
                await ensureUserDocument(uid: result.user.uid, email: result.user.email, displayName: displayName)
            } catch {
                errorMessage = Self.friendlyMessage(for: error)
            }
        }
    }

    // MARK: - Firestore

    private func ensureUserDocument(uid: String, email: String?, displayName: String?) async {
        let doc = Firestore.firestore().collection("users").document(uid)
        do {
            let snapshot = try await doc.getDocument()
            guard !snapshot.exists else { return }
            var data: [String: Any] = [
                "uid": uid,
                "createdAt": FieldValue.serverTimestamp()
            ]
            data["email"] = email
            data["displayName"] = displayName
            try await doc.setData(data)
        } catch {
            // Non-blocking: isSignedIn reflects Firebase Auth state only (spec §6).
            // The doc gets created lazily the next time this runs, e.g. next launch.
        }
    }

    // MARK: - Nonce (Apple Sign In replay protection)

    nonisolated static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(status == errSecSuccess, "Unable to generate nonce: \(status)")

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    nonisolated static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Errors

    private static func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain else {
            return "Something went wrong. Please try again."
        }
        switch AuthErrorCode(rawValue: nsError.code) {
        case .wrongPassword, .invalidCredential, .userNotFound:
            return "Incorrect email or password."
        case .emailAlreadyInUse:
            return "An account already exists with that email."
        case .invalidEmail:
            return "Enter a valid email address."
        case .networkError:
            return "No connection. Check your network and try again."
        case .weakPassword:
            return "Password must be at least 6 characters."
        case .tooManyRequests:
            return "Too many attempts. Try again later."
        case .userDisabled:
            return "This account has been disabled."
        default:
            return "Something went wrong. Please try again."
        }
    }
}
