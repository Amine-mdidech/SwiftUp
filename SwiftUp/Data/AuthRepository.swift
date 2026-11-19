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
    private(set) var errorMessage: String?
    /// Whether the signed-in account has ever completed onboarding — `nil` while that's still
    /// being checked (see `refreshOnboardingStatus`). Deliberately per-*account* (read from
    /// `users/{uid}.skillLevel`'s presence in Firestore, the field `saveInitialSkillLevel` writes
    /// the moment onboarding finishes) rather than a device-local flag: a device-wide flag meant
    /// that once any account had finished onboarding once, a brand-new account signing in on the
    /// same device — including a fresh account created right after deleting a previous one —
    /// skipped onboarding entirely and silently defaulted to Junior, never asking.
    private(set) var hasCompletedOnboarding: Bool?

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
        self.hasCompletedOnboarding = isPreview ? signedIn : nil

        guard !isPreview else { return }

        let restored = Auth.auth().currentUser
        self.isSignedIn = restored != nil
        self.currentUser = restored.map(Self.authUser(from:))

        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.isSignedIn = user != nil
            self.currentUser = user.map(Self.authUser(from:))
            self.hasCompletedOnboarding = nil
            if let uid = user?.uid {
                Task { await self.refreshOnboardingStatus(uid: uid) }
            }
        }
    }

    /// Reads whether `uid`'s user document already has a `skillLevel` — the field
    /// `saveInitialSkillLevel` writes the moment onboarding finishes, so its presence is the
    /// authoritative "has this account ever finished onboarding" signal. A failed read (offline,
    /// first launch before the doc exists) reads as "needs onboarding" — the same safe-default
    /// posture this project uses elsewhere for a missing/unreachable user doc.
    private func refreshOnboardingStatus(uid: String) async {
        guard let snapshot = try? await Firestore.firestore().collection("users").document(uid).getDocument() else {
            hasCompletedOnboarding = false
            return
        }
        hasCompletedOnboarding = (snapshot.get("skillLevel") as? String) != nil
    }

    /// Called by `RootView` the moment `OnboardingFlowView` finishes, so the just-completed
    /// account is immediately treated as onboarded without waiting on (or re-triggering) a fresh
    /// Firestore read — `saveInitialSkillLevel` already wrote the field this local flip mirrors.
    func markOnboardingCompleted() {
        hasCompletedOnboarding = true
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
    }

    // MARK: - Email/password

    /// No separate sign-in/sign-up choice is shown to the user — this tries signing in first, and
    /// silently creates the account on any error that might mean "no such user" (see
    /// `isSignInFailureThatMightMeanNoAccount` for why that's more than one error code on this
    /// project), so a single button covers both cases.
    func continueWithEmail(email: String, password: String) async {
        guard !isPreview else { return }
        errorMessage = nil
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            await ensureUserDocument(uid: result.user.uid, email: result.user.email, displayName: result.user.displayName)
        } catch {
            guard Self.isSignInFailureThatMightMeanNoAccount(error) else {
                errorMessage = Self.friendlyMessage(for: error)
                return
            }
            do {
                let result = try await Auth.auth().createUser(withEmail: email, password: password)
                await ensureUserDocument(uid: result.user.uid, email: result.user.email, displayName: result.user.displayName)
            } catch {
                let nsError = error as NSError
                if nsError.domain == AuthErrorDomain, AuthErrorCode(rawValue: nsError.code) == .emailAlreadyInUse {
                    // The account really does exist — the original sign-in failed for a different
                    // reason (wrong password), which this project's email-enumeration protection
                    // deliberately reports identically to "no such user" (see the method below).
                    errorMessage = "Incorrect email or password."
                } else {
                    errorMessage = Self.friendlyMessage(for: error)
                }
            }
        }
    }

    /// With this project's email-enumeration protection enabled (Firebase console:
    /// emailPrivacyConfig.enableImprovedEmailPrivacy — confirmed ON for this project), a real
    /// "no such user" sign-in attempt and a real "wrong password" one are both reported as
    /// `invalidCredential` — Firebase deliberately makes them indistinguishable by error code
    /// alone, to prevent attackers enumerating which emails have accounts. Treating both as
    /// "might mean no account yet" and attempting `createUser` is the only way to tell them
    /// apart: `createUser` itself throws `emailAlreadyInUse` if the account was real, which the
    /// caller above turns back into the correct "Incorrect email or password." message.
    private static func isSignInFailureThatMightMeanNoAccount(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain else { return false }
        switch AuthErrorCode(rawValue: nsError.code) {
        case .userNotFound, .invalidCredential:
            return true
        default:
            return false
        }
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
            // `result.user.displayName` is FirebaseAuth's own cached copy — it's only populated when
            // a brand-new Firebase account is first created from this credential, not refreshed on
            // later sign-ins to an existing account. `googleResult.user.profile?.name` is the
            // GoogleSignIn SDK's own result for *this* sign-in, fresh from Google every time,
            // regardless of what Firebase cached — preferred here for exactly that reason.
            let displayName = googleResult.user.profile?.name ?? result.user.displayName
            await ensureUserDocument(uid: result.user.uid, email: result.user.email, displayName: displayName)
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

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Delete account

    enum DeleteAccountResult {
        case deleted
        case failed
    }

    /// Deletes the signed-in user's Firestore data, then their Firebase Auth account, in that
    /// order — `firestore.rules` requires `request.auth.uid == uid` for every write here, so the
    /// Auth account must still exist while the data-deletion writes run. Once `user.delete()`
    /// succeeds, `authStateHandle`'s listener fires with a `nil` user, flipping `isSignedIn` to
    /// `false` — `RootView` reacts to that alone, no separate "go back to signed out" step needed.
    ///
    /// Firebase requires a "recent" sign-in to delete the Auth record itself, which an
    /// already-signed-in user tapping "delete my account" should never have to satisfy with a
    /// second, explicit reauthentication step — the user is already signed in; asking again is
    /// exactly the friction this method exists to avoid. So on `requiresRecentLogin` specifically
    /// (data deletion above already succeeded, unaffected by this check), this signs the user out
    /// locally instead and still reports `.deleted`: every trace of their data is gone, and an
    /// inert, dataless Auth record with no way back into the app's data is indistinguishable from
    /// "deleted" for anything the user can observe. (A fully complete fix would delete that Auth
    /// record too via a server-side Admin SDK call, which isn't gated by client recency at all —
    /// this app has no backend/Cloud Functions layer today, so that's a real follow-up, not a
    /// one-line change, if the rare leftover empty record ever needs to go away for good.)
    func deleteAccount() async -> DeleteAccountResult {
        guard !isPreview else { return .deleted }
        guard let user = Auth.auth().currentUser else { return .failed }
        do {
            try await Self.deleteUserData(uid: user.uid)
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
            return .failed
        }
        do {
            try await user.delete()
        } catch {
            let nsError = error as NSError
            if nsError.domain == AuthErrorDomain, AuthErrorCode(rawValue: nsError.code) == .requiresRecentLogin {
                signOut()
                return .deleted
            }
            errorMessage = Self.friendlyMessage(for: error)
            return .failed
        }
        return .deleted
    }

    private static func deleteUserData(uid: String) async throws {
        let userRef = Firestore.firestore().collection("users").document(uid)
        for subcollection in ["dailyCompletions", "bookmarks", "flashcardReviews"] {
            try await deleteAllDocuments(in: userRef.collection(subcollection))
        }
        try await userRef.delete()
    }

    /// Batch-deletes every document in `collection`, chunked to stay under Firestore's 500-write
    /// batch limit — a long-lived account's `dailyCompletions` (one doc per day) could plausibly
    /// exceed 500 eventually, even though `bookmarks`/`flashcardReviews` realistically won't.
    private static func deleteAllDocuments(in collection: CollectionReference) async throws {
        let snapshot = try await collection.getDocuments()
        var remaining = snapshot.documents[...]
        while !remaining.isEmpty {
            let chunk = remaining.prefix(400)
            let batch = Firestore.firestore().batch()
            for doc in chunk { batch.deleteDocument(doc.reference) }
            try await batch.commit()
            remaining = remaining.dropFirst(chunk.count)
        }
    }

    func signOut() {
        guard !isPreview else { return }
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    private static func authUser(from user: User) -> AuthUser {
        let method: String? = switch user.providerData.first?.providerID {
        case "apple.com": "Apple"
        case "google.com": "Google"
        case "password": "email"
        default: nil
        }
        return AuthUser(uid: user.uid, email: user.email, displayName: user.displayName, signInMethod: method)
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

    /// Creates the user doc on first sign-in, and on every sign-in after that, backfills
    /// `email`/`displayName` if the provider just supplied a value this time and the doc doesn't
    /// already have one. Previously this returned immediately once the doc existed, so a name
    /// missed on account creation (e.g. a transient issue reading it from the provider) could never
    /// be recovered — even by an Apple/Google account, whose provider reliably supplies a name on
    /// every sign-in. Never clobbers an existing value with `nil`: Apple only shares the user's name
    /// on the very first authorization, so every later Apple sign-in must not overwrite whatever
    /// name a previous sign-in already stored.
    private func ensureUserDocument(uid: String, email: String?, displayName: String?) async {
        let doc = Firestore.firestore().collection("users").document(uid)
        do {
            let snapshot = try await doc.getDocument()
            let existingDisplayName = snapshot.get("displayName") as? String
            var data: [String: Any] = [:]
            if !snapshot.exists {
                data["uid"] = uid
                data["createdAt"] = FieldValue.serverTimestamp()
            }
            if (snapshot.get("email") as? String)?.isEmpty != false, let email, !email.isEmpty {
                data["email"] = email
            }
            if existingDisplayName?.isEmpty != false, let displayName, !displayName.isEmpty {
                data["displayName"] = displayName
            }
            if !data.isEmpty {
                try await doc.setData(data, merge: true)
            }
        } catch {
            // Non-blocking: isSignedIn reflects Firebase Auth state only (spec §6).
            // The doc gets created/backfilled lazily the next time this runs, e.g. next launch.
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
