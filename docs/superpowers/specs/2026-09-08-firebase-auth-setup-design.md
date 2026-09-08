# Firebase Setup + Auth — Design

Sub-project 1 of 6 in the backend build-out (see decomposition below). Cross-reference: `requirements.md` §3 (Authentication), §4 (backend-driven content).

## 0. Backend decomposition (context)

This app currently has zero backend: every repository (`ProfileRepository`, `LeaderboardRepository`, `QuestionRepository`, `InterviewRepository`) reads static bundled JSON. Firebase was chosen as the backend platform (BaaS: Auth + Firestore + Cloud Messaging + Analytics + Remote Config), covering the full v1 non-functional scope without hand-rolling a server, appropriate for a solo/low-ops build. The build-out is split into 6 sub-projects, each with its own spec/plan/implementation cycle:

1. **Firebase project setup + Auth + Firestore** (this spec)
2. Profile/XP/streak sync (Firestore-backed `ProfileRepository`)
3. Leaderboard (real-time Firestore query)
4. Remote content (question bank as CMS, replacing bundled JSON)
5. Push notifications (FCM)
6. Analytics (Firebase Analytics events)

Order follows the dependency chain — nothing else can be "real" until there's a signed-in user to attach data to.

## 1. Goal

Stand up a Firebase project, add Sign in with Apple + email/password authentication, and gate the app on it — ahead of the existing onboarding flow. Create a bare Firestore `users/{uid}` document on first sign-in as the foundation sub-project 2 builds on. No other repository changes in this pass; profile/leaderboard/content stay on bundled JSON until their own sub-projects.

Out of scope for this pass: profile data sync, real leaderboard, remote content/CMS, push notifications, analytics — all covered by later sub-projects.

## 2. Manual setup (not code)

Before implementation can be verified end-to-end, the following happens in the Firebase console (developer action, not scripted):

- Create a Firebase project
- Register the iOS app (bundle id) in that project, download `GoogleService-Info.plist`
- Enable **Sign in with Apple** and **Email/Password** providers under Authentication
- Enable Firestore (production mode, region selection)
- In Xcode: enable the "Sign in with Apple" capability on the app target

## 3. Architecture

`AuthRepository` (`@Observable`, mirrors the existing repository pattern) wraps Firebase Auth and exposes sign-in state to the view layer. `RootView` gets a new outer gate layered above the existing onboarding gate:

```
RootView
  not signed in   → AuthView
  signed in        → (existing) hasCompletedOnboarding gate
                        false → OnboardingFlowView
                        true  → MainTabView
```

Firebase is initialized once, in `SwiftUpApp.init()`, via `FirebaseApp.configure()`.

## 4. Components

- **`SwiftUp/Data/AuthRepository.swift`** — `@Observable`, conforms to `AuthRepositoryProtocol`. Exposes `isSignedIn: Bool`, `currentUser: AuthUser?` (a small local struct: `uid`, `email`, `displayName` — not the raw Firebase type, to keep the rest of the app decoupled from the SDK). Methods: `signInWithApple()`, `signUp(email:password:)`, `signIn(email:password:)`, `signOut()`. Subscribes to Firebase's `addStateDidChangeListener` on init to keep `isSignedIn`/`currentUser` live.
- **`SwiftUp/Features/Auth/AuthView.swift`** — Sign in with Apple button (SwiftUI `SignInWithAppleButton`) plus an email/password form with a sign-in/sign-up mode toggle. Inline validation (non-empty email format, password length) before calling the repository.
- **Firebase SPM package** (`firebase-ios-sdk`): modules `FirebaseAuth`, `FirebaseFirestore`, `FirebaseCore`.
- **`firestore.rules`** (checked into repo root, deployed via Firebase console or CLI): a user may only read/write their own `users/{uid}` document.
  ```
  match /users/{uid} {
    allow read, write: if request.auth != null && request.auth.uid == uid;
  }
  ```
- **`RootView.swift`** — updated to check `authRepository.isSignedIn` first, ahead of the existing `hasCompletedOnboarding` check.

## 5. Data flow

1. App launch → `FirebaseApp.configure()` → `AuthRepository` attaches its auth-state listener.
2. `RootView` observes `authRepository.isSignedIn`. If false, shows `AuthView`.
3. User taps Sign in with Apple, or fills the email/password form and submits.
4. On success, Firebase Auth returns a user. `AuthRepository` checks Firestore for `users/{uid}`; if it doesn't exist, creates it with `{ uid, email, displayName, createdAt }`.
5. `isSignedIn` becomes true (driven by the Auth state, not the Firestore write — see error handling), `RootView` proceeds to the existing onboarding gate exactly as today.
6. Sign-out (entry point added to `SettingsView` in this pass) calls `authRepository.signOut()`, returning to `AuthView`.

## 6. Error handling

- Firebase Auth errors (wrong password, email already in use, malformed email, network failure) are mapped to a short user-facing message shown via alert on `AuthView`.
- Apple Sign In cancellation (user dismisses the system sheet) is a silent no-op, not an error state.
- If the Firestore user-doc write fails (e.g. transient network issue), the user is **not** blocked from proceeding — `isSignedIn` reflects Firebase Auth state only. The repository retries the doc-existence check lazily on next launch/read rather than blocking login on it.

## 7. Testing

- `AuthRepositoryProtocol` + a `FakeAuthRepository` (mirrors the existing bundle-based fake pattern) for SwiftUI previews and any logic-level tests (email/password validation rules).
- Firebase Auth/Firestore itself is not unit-tested (external service) — covered by manual verification.
- Manual: build + run in Simulator, exercise sign-up (email/password), sign-out, sign-in, and Sign in with Apple on a device/simulator signed into a sandbox Apple ID; confirm `users/{uid}` document appears in the Firestore console on first sign-up.

## 8. Open implementation decisions (flagged, not blocking)

- **Display name for email/password sign-up**: requirements.md doesn't specify a name-entry step for email sign-up. Default: leave `displayName` nil for email/password accounts (Apple Sign In provides one on first authorization only, per Apple's privacy model); can be added as a profile-setup step in sub-project 2 if needed.
- **Account deletion**: not in scope for this pass; add when Settings/account management is built out.
