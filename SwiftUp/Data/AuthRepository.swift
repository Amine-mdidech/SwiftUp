import Foundation
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit

@Observable
final class AuthRepository: NSObject {
    private(set) var isSignedIn: Bool
    private(set) var currentUser: AuthUser?
    var errorMessage: String?

    private let isPreview: Bool
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init(isPreview: Bool = false, signedIn: Bool = false) {
        self.isPreview = isPreview
        self.isSignedIn = isPreview ? signedIn : false
        self.currentUser = (isPreview && signedIn)
            ? AuthUser(uid: "preview-user", email: "preview@example.com", displayName: "Preview User")
            : nil
        super.init()

        guard !isPreview else { return }
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

    func signUp(email: String, password: String) async {
        errorMessage = nil
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            await ensureUserDocument(uid: result.user.uid, email: result.user.email, displayName: result.user.displayName)
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    // MARK: - Sign in with Apple

    func handleAppleSignIn(result: Result<ASAuthorization, Error>, rawNonce: String) async {
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

    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(status == errSecSuccess, "Unable to generate nonce: \(status)")

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Errors

    private static func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        switch AuthErrorCode(rawValue: nsError.code) {
        case .wrongPassword, .invalidCredential:
            return "Incorrect email or password."
        case .emailAlreadyInUse:
            return "An account already exists with that email."
        case .invalidEmail:
            return "Enter a valid email address."
        case .networkError:
            return "No connection. Check your network and try again."
        case .weakPassword:
            return "Password must be at least 6 characters."
        default:
            return "Something went wrong. Please try again."
        }
    }
}
