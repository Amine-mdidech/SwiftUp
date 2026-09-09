# Remote Question Bank — Design

Sub-project 4 of 6 in the backend build-out (see `docs/superpowers/specs/2026-09-08-firebase-auth-setup-design.md` §0). Sub-project 1 (Firebase Auth) is done and merged. Cross-reference: `requirements.md` §2.1 (Daily Quiz), §2.2 (Gamification), §4 (backend-driven content).

## 1. Goal

Move the daily quiz question bank from bundled JSON (`SwiftUp/Resources/questions.json`, 5 static questions) to Firestore, with three things the static version never had:

- **A real bank per skill level** (Junior/Mid/Senior), big enough that "today's five" is a genuine daily selection, not a fixed set.
- **Per-user daily rotation**: 4 questions the user has never answered before, plus 1 repeat (their oldest-answered question) — computed client-side, no server infrastructure.
- **Skill-level progression**: exhausting a level's bank promotes the user to the next level (Junior→Mid→Senior) instead of just repeating forever.

Out of scope for this pass: the Interview Prep bank (`interview_questions.json`) stays bundled JSON — a candidate for its own later sub-project, same pattern. Full XP/streak/profile sync (sub-project 2) is untouched — this pass adds only the one Firestore field needed for repeat-avoidance (`answeredQuestionIDs`), not a general answer-history system. The numeric XP `Level` (1-12, `ProfileRepository`/`levels.json`) is a separate, unrelated concept and is not touched by this pass.

## 2. Manual setup (not code)

- **Firebase console**: no new provider/config needed — reuses the existing Firestore database from sub-project 1.
- **Service account key** for the one-time seed script: Firebase console → Project settings → Service accounts → "Generate new private key". Downloads a JSON file. This grants admin access to the Firestore project — **never commit it**; it's referenced from a gitignored path.

## 3. Firestore schema

**`questions/{questionId}`** — one document per question:

```
{
  id: string              // same as document ID
  level: string            // "junior" | "mid" | "senior"
  topic: string
  format: string            // "multipleChoice" | "trueFalse" | "spotTheBug" | "fillInTheBlank"
  prompt: string
  codeSnippet: string | null
  options: [{ id: string, text: string }]
  correctOptionID: string
  explanation: string
  xp: number
}
```

Same shape as the current `Question` model, plus `level`. `format`/option shape unchanged so `QuizQuestionView`/`QuizSession` need no changes — only `QuestionRepository` changes.

**`users/{uid}`** gains two fields (extending sub-project 1's bare doc):

```
skillLevel: string                        // "junior" | "mid" | "senior" — set once after onboarding, promoted over time
levelOverride: string | null                // "junior" | "mid" | "senior" | null — set from Settings; null means "use skillLevel" ("Adaptive")
answeredQuestionIDs: { [questionId]: Timestamp }   // map, not array — value is when the user answered it, used to pick the oldest-first repeat
```

**Firestore rules** (`firestore.rules`), adding a `questions` block:

```
match /questions/{questionId} {
  allow read: if request.auth != null;
  allow write: if false; // seeded only via the admin service-account script, which bypasses rules
}
```

The existing `users/{uid}` rule (owner-only read/write) already covers the two new fields — no change needed there.

## 4. Selection algorithm

Runs client-side in `QuestionRepository` on load (app launch / day change), given the user's `skillLevel` and `answeredQuestionIDs`:

1. Fetch all questions at the user's current `skillLevel` (one Firestore query, `where level == skillLevel`; cached locally by the SDK after the first fetch).
2. Compute `unanswered = bank - answeredQuestionIDs`.
3. **If `unanswered` is empty and `skillLevel != .senior`**: promote — write the next level to `users/{uid}.skillLevel` (junior→mid, mid→senior), re-fetch that level's bank, and pick all 5 from it (guaranteed unseen, since the user has never touched this level before). No repeat slot needed this day.
4. **Otherwise**: pick up to 4 from `unanswered`, seeded by a hash of `(uid, today's date)` so the picks are stable across app opens within the same day but change tomorrow. Fill the 5th slot with the question in `answeredQuestionIDs` the user answered **longest ago** (requires each answered ID to carry a timestamp — see §5). If `unanswered` has fewer than 4 (small bank, active user, not yet at the promotion trigger), fill the remaining slots from the answered pool too, oldest-first — the "4 new" target relaxes gracefully rather than erroring.
5. At `senior` with everything answered: same as step 4's fallback (no level left to promote to) — the day's 5 are all repeats, oldest-answered first.

## 5. Answer tracking

`answeredQuestionIDs` needs "answered when" for the oldest-first repeat rule, so it's actually stored as a **map**, not a plain array — `answeredQuestionIDs: { [questionId]: timestamp }` in Firestore (a map serializes fine as `[String: Timestamp]` in Swift). When a quiz session finishes (`QuizSummaryView`'s completion point, matching where `TodayFlowView.finish()` already resets state), the app writes the 5 answered IDs into that map with `FieldValue.serverTimestamp()`-equivalent client timestamps merged in (a Firestore `update` with dotted field paths, e.g. `answeredQuestionIDs.q7`), non-blocking on failure — same "don't strand the user on a write failure" pattern as `AuthRepository.ensureUserDocument`.

## 6. Level persistence

- `SkillAssessmentView`'s `onContinue: (SkillLevel) -> Void` callback (currently discarded by `OnboardingFlowView`) now writes the chosen level to `users/{uid}.skillLevel`, once, right after onboarding.
- `SettingsView`'s existing "Adaptive/Junior/Mid/Senior" `SegmentedPicker` (currently a visual-only mock, doesn't persist or affect anything) becomes real: selecting a specific level writes an **override** that `QuestionRepository` prefers over the stored `skillLevel` for picking today's questions. "Adaptive" means "use my stored `skillLevel`" — true adaptive-difficulty logic is still v2 per requirements.md §2.1. The override is a separate field (`levelOverride: string?`) so the underlying promotion-tracked `skillLevel` is never clobbered by a manual settings change.

## 7. `QuestionRepository`

Becomes `@Observable` with an async load instead of a synchronous bundle decode:

```swift
@Observable
final class QuestionRepository {
    private(set) var todayQuestions: [Question] = []
    private(set) var isLoading = false

    func load(for uid: String) async { ... }
}
```

Bundled `questions.json` stays as a last-resort fallback — used only if the initial Firestore fetch fails with nothing cached yet (matching `ProfileRepository`'s existing default-value-on-failure pattern). Firestore's SDK persists reads locally by default, so normal offline use after the first successful fetch continues to work without extra code.

## 8. Content authoring + migration

I'll author a new bank — **12 questions per level, 36 total** — as a local JSON file (`scripts/seed-questions.json` or similar, not bundled into the app), covering the topics already established in the app (Concurrency, Memory/ARC, SwiftUI state, Architecture, Networking, Testing, Xcode/tooling, App lifecycle), spread across the existing question formats. A one-time Python script (`scripts/seed_questions.py`, using the `firebase-admin` package) reads that JSON and writes each entry as a `questions/{id}` document using the service-account key from §2. This script and its input JSON are dev tooling, not shipped in the app bundle. Future bank growth after this point is just adding Firestore documents — no app release, no script re-run needed (though the script stays useful for future bulk additions).

## 9. Error handling

- Firestore query failure with a warm local cache: SDK serves cached data transparently, no user-visible error.
- Failure with no cache (first launch, no network): fall back to bundled `questions.json`, matching existing `ProfileRepository` failure-mode conventions in this codebase.
- `answeredQuestionIDs` write failure on quiz completion: non-blocking — the user isn't blocked from continuing, and worst case that one question can be re-selected as unseen later (acceptable; not a data-integrity issue).
- Skill-level promotion write failure: retried lazily next launch, same non-blocking pattern as `AuthRepository.ensureUserDocument`.

## 10. Testing

- Unit tests (Swift Testing, no Firebase): the selection algorithm's pure logic — given a bank + answered-map + level, does it correctly (a) promote when unanswered is empty, (b) pick 4 unseen + 1 oldest-repeat in the normal case, (c) gracefully fill from repeats when unseen < 4, (d) cap out at `senior`. Extract this as a pure function (e.g. `QuestionSelector.pickToday(bank:answered:level:seed:) -> (questions: [Question], promotedTo: SkillLevel?)`) so it's testable without touching Firestore, mirroring how `AuthValidation`/nonce helpers in `AuthRepository` are pure and directly tested.
- Manual: verify actual Firestore fetch, promotion write, and answered-map write against the real project once seeded.

## 11. Open implementation decisions (flagged, not blocking)

- **Seed script language**: Python + `firebase-admin`, since no Node/Python Firebase tooling exists yet in this repo either way — Python chosen for minimal setup (`pip install firebase-admin` vs. `npm init` + package.json for a one-off script).
- **Where "answered" is recorded relative to XP/streak** (sub-project 2 will likely want the same completion event): this pass writes only to `answeredQuestionIDs`; sub-project 2 can extend the same completion hook rather than needing a new one.
