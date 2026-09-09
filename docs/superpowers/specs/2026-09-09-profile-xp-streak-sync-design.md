# Profile/XP/Streak Sync — Design

Sub-project 2 of 6 in the backend build-out (see `docs/superpowers/specs/2026-09-08-firebase-auth-setup-design.md` §0). Sub-project 1 (Firebase Auth) and sub-project 4 (Remote question bank) are done and merged. Cross-reference: `requirements.md` §2.2 (Gamification System).

## 1. Goal

Move `ProfileRepository` from fully static bundled JSON (`profile.json`, `achievements.json`, `topics.json` — currently showing a fixed mock user "Maya Reyes" regardless of who's signed in) to real, Firestore-backed per-user data: identity, XP/level, streak (with a freeze/grace mechanic), accuracy by topic, and achievement unlocking — all driven by actual daily-quiz completions.

`levels.json` (the 12-level XP ladder: number/title/xpThreshold) stays bundled and static — it's reference content, not per-user data, same reasoning as `SkillLevel` in sub-project 4.

Out of scope for this pass:
- **Leaderboard** (sub-project 3) — untouched, stays on bundled mock data.
- **Interview Prep sessions/FAQ-review tracking** — "Live Coding Interview Sessions" (requirements.md §2.3) aren't built at all yet (no session concept exists in `InterviewRepository`/`InterviewBankView`). Achievements gated on this (`a04` First interview session, `a16` Interview ready, `a22` Second session) and on leaderboard rank (`a24` Top of the board) keep their current static/locked definitions in the catalog but have **no real unlock path** in this pass — they're flagged `.unbuildable` (§4) rather than silently dropped, ready to wire up once those subsystems exist.
- Push notifications, analytics (sub-projects 5, 6).

## 2. Firestore schema

**`users/{uid}`** gains (extending sub-projects 1 & 4's existing fields — `email`, `displayName`, `createdAt`, `skillLevel`, `levelOverride`, `answeredQuestionIDs`):

```
totalXP: number                                    // cumulative XP across all completed sessions
totalQuestionsAnswered: number                      // all-time attempt count, including repeats
                                                     // (distinct from answeredQuestionIDs, which tracks
                                                     // unique IDs for sub-project 4's spaced-repetition —
                                                     // a repeat-answer increments this but not that map)
streakDays: number
freezesAvailable: number                            // 0-3, banked
lastCompletedDate: string | null                    // "yyyy-MM-dd", local calendar day of last full completion
topicStats: { [topic: string]: { correct: number, total: number } }   // keyed by the question's own
                                                     // freeform `topic` string — no fixed taxonomy
earnedAchievementIDs: { [achievementId: string]: Timestamp }          // mirrors answeredQuestionIDs's shape
```

**New subcollection `users/{uid}/dailyCompletions/{yyyy-MM-dd}`** — one document per calendar day the user finishes all 5 questions:

```
{
  correctCount: number    // 0-5
  xpEarned: number
}
```

This is the source of truth the streak/freeze engine consults, and it's also what makes the windowed achievements (`a01` "6 of 7 days ≥4/5", `a15` "every day this month ≥4/5") computable — a plain running counter on `users/{uid}` can't answer "how many of the last 7 calendar days," only a dated log can. Document IDs are `yyyy-MM-dd` so a date-range query (`>= startDate`, `<= endDate`) is a single indexed Firestore query, no full collection scan.

**Firestore rules**: no new `match` block needed — the existing `users/{uid}` owner-only rule already covers the doc's new fields, and a subcollection under a `match /users/{uid}` block needs its own nested rule. Add:

```
match /users/{uid} {
  allow read, write: if request.auth != null && request.auth.uid == uid;
  match /dailyCompletions/{date} {
    allow read, write: if request.auth != null && request.auth.uid == uid;
  }
}
```

## 3. Achievement catalog restructuring

Today's `achievements.json` mixes static catalog data (title, detail, sealKind, xpReward) with per-user runtime state (status, earnedDateDisplay, progressCurrent/Target) baked into the same 24 mock entries. Split these:

**Bundled, static** — `SwiftUp/Resources/achievement_catalog.json`, one entry per achievement, catalog fields only plus a new `criterion`:

```
{
  "id": "a05", "title": "Seven in a row", "detail": "Your first full week's streak",
  "sealKind": "streakMilestone", "xpReward": 50,
  "criterion": { "kind": "streak", "days": 7 }
}
```

`criterion` is a flat struct (matching this codebase's plain-`Codable`-struct style — no custom `Decodable`, no associated-value enum): `kind: String` plus optional `topic: String?`, `minAccuracy: Int?`, `minAnswered: Int?`, `count: Int?`, `days: Int?`. `kind` values: `streak`, `topicMastery`, `totalAnswered`, `perfectDays`, `perfectWeek`, `perfectMonth`, `onboarded`, `level`, `unbuildable` (the 4 achievements named in §1 — carries no other fields, `AchievementEngine` always renders these `.locked` with no progress).

Runtime, computed — `Achievement` (the existing model) keeps `status`/`earnedDateDisplay`/`progressCurrent`/`progressTarget`, but these are now computed by `AchievementEngine.evaluate(...)` (§4) at load time from live stats, never read from a file.

One simplification from the current mock content: `a02` "Thirty in a row"'s detail ("A 30-day streak, no freezes spent") drops the "no freezes spent" qualifier — tracking which specific days within a streak consumed a freeze is meaningfully more state for one achievement's flavor text, when every other streak-length achievement (`a05`, `a10`, `a12`, `a21`) is already a plain length check. Its `criterion` becomes the same shape as those: `{ "kind": "streak", "days": 30 }`.

Topic-mastery achievements (`a03`, `a07`, `a13`, `a14`, `a19`, `a20`) get their `criterion.topic` value aligned to the exact `topic` strings that exist on real seeded questions (e.g. `scripts/seed-questions.json`'s `"Architecture"`, `"Concurrency"`, `"Networking"`, `"Swift language"`, `"Testing"`) — picked in the implementation plan, not itemized here, since it's a mechanical lookup against current seed content, not a design decision.

## 4. Pure engines (Firebase-free, Swift Testing–covered)

Three new types, same shape as sub-project 4's `QuestionSelector` — pure functions of their inputs, no I/O:

**`StreakCalculator`**
```swift
static func apply(
    lastCompletedDate: String?, streakDays: Int, freezesAvailable: Int, today: String
) -> (streakDays: Int, freezesAvailable: Int)
```
- `today == lastCompletedDate`: no-op (already recorded today — completion is idempotent per day).
- `today` is exactly one calendar day after `lastCompletedDate` (or `lastCompletedDate == nil`, i.e. first-ever completion): `streakDays + 1`. Every time the new `streakDays` crosses a multiple of 7, `freezesAvailable = min(freezesAvailable + 1, 3)`.
- `today` is exactly two days after `lastCompletedDate` (exactly one calendar day missed) **and** `freezesAvailable > 0`: consume one freeze (`freezesAvailable - 1`) and treat it like the "one day later" case above — streak continues (`streakDays + 1`), still eligible for the same +1/week accrual. A freeze forgives exactly one missed day.
- Any wider gap (two or more days missed), or a one-day-missed gap with `freezesAvailable == 0`: `streakDays` resets to `1` (today counts as day one of a new streak); `freezesAvailable` is unchanged in this branch (not consumed — there's nothing a single freeze could have covered in a multi-day gap).

**`LevelCalculator`**
```swift
static func level(for totalXP: Int, ladder: [LevelInfo]) -> (number: Int, title: String, xpForCurrentLevel: Int, xpForNextLevel: Int)
```
Finds the highest `xpThreshold <= totalXP` in `ladder` (sorted by `number`); `xpForNextLevel` is the next entry's threshold, or the current level's own threshold again if already at the ladder's ceiling (level 12) — matches `UserProfile.xpToNextLevel`'s existing `max(0, ...)` clamp so it reads as "maxed out," not a negative number.

**`AchievementEngine`**
```swift
static func evaluate(catalog: [AchievementDefinition], stats: UserStats) -> [Achievement]
```
`UserStats` bundles: `totalXP`, `streakDays`, `totalQuestionsAnswered`, `topicStats: [String: (correct: Int, total: Int)]`, `recentCompletions: [(date: String, correctCount: Int)]` (last 31 days — covers both the 7-day and calendar-month windows), `onboarded: Bool`. For each catalog entry, evaluates its `criterion` against `stats` to produce a `status` (`earned` once the threshold is met — `earnedDateDisplay` comes from `earnedAchievementIDs`'s stored timestamp, not recomputed; `inReach` if partial progress exists; `locked` otherwise) and `progressCurrent`/`progressTarget` where the criterion has a natural progress metric (streak/totalAnswered/topicMastery/perfectDays; perfectWeek/perfectMonth/onboarded/level/unbuildable report no progress, matching today's mock data's `null` progress on non-progress-bar achievements).

## 5. Completion flow

`TodayFlowView.finish()` is the existing single "quiz session completed" event (already identified in sub-project 4's spec as this sub-project's extension point) — it already calls `QuestionRepository.recordAnswered(...)`. It gains a second call: `ProfileRepository.recordCompletion(session, for: uid) async`, which:

1. Reads the current `users/{uid}` doc.
2. Computes topic deltas from `session.questions` × `session.correctCount`-per-question (each question already carries its own `topic` and whether it was answered correctly is derivable from `session`'s existing per-question answer state).
3. Runs `StreakCalculator` and `LevelCalculator`-adjacent totals (`totalXP += session.totalXPEarned`, `totalQuestionsAnswered += session.questions.count`).
4. Re-evaluates `AchievementEngine` against the updated stats to find newly-`earned` achievements not already in `earnedAchievementIDs`.
5. Writes: the updated `users/{uid}` fields, the new `earnedAchievementIDs` entries, and the `dailyCompletions/{today}` doc — as one batched Firestore write (`WriteBatch`), matching the atomicity the existing `answeredQuestionIDs` update doesn't need but this multi-field update does (a partial write here would desync `totalXP` from `dailyCompletions`, which the streak engine depends on next time).
6. Updates local `@Observable` state directly from the computed result (not a re-fetch) so the Profile tab reflects the change immediately.

Non-blocking on failure, consistent with every other write in this codebase (`AuthRepository.ensureUserDocument`, sub-project 4's `recordAnswered`) — the user is never blocked leaving the quiz screen; worst case the next `load(for:)` re-derives correct state from whatever did persist.

## 6. `ProfileRepository`

Rewritten to the same async/`@Observable` shape as sub-project 4's `QuestionRepository`:

```swift
@Observable
final class ProfileRepository {
    private(set) var profile: UserProfile
    private(set) var topics: [TopicAccuracy]      // dynamic, derived from topicStats — no bundled topics.json anymore
    private(set) var achievements: [Achievement]    // computed via AchievementEngine
    let levels: [LevelInfo]                          // static, bundled, loaded synchronously in init
    private(set) var isLoading = false

    init() { levels = ...; profile = <empty/default>; ... }   // no Firebase touch
    static func preview(bundle: Bundle = .main) -> ProfileRepository   // synchronous bundled fallback, never touches Firestore
    func load(for uid: String) async { ... }
    func recordCompletion(_ session: QuizSession, for uid: String) async { ... }
}
```

`profile.json`'s mock content (name "Maya Reyes" etc.) becomes the bundled **fallback-only** payload (`ProfileRepository.preview()`, and `load(for:)`'s failure path if Firestore is unreachable with nothing cached) — same fallback pattern as sub-project 4's `questions.json`. `achievements.json`/`topics.json` retire; `achievement_catalog.json` (§3) replaces the former, and topics render from `topicStats` directly (empty list, not an error, for a brand-new user with no answered questions yet).

`RootView` holds `profileRepository` as `@State` (not `let`) — same reasoning as `questionRepository` in sub-project 4, and `TodayFlowView`/`ProfileHomeView` read it via `@Environment`.

## 7. Error handling

- `load(for:)` Firestore failure with a warm SDK cache: served transparently, no user-visible error (same as sub-project 4).
- `load(for:)` failure with no cache (first launch, offline): falls back to bundled `profile.json`/empty topics/catalog-with-all-locked-achievements, matching sub-project 4's fallback convention.
- `recordCompletion(...)` write failure: non-blocking (§5) — XP/streak/achievements for that session are lost, not corrupted; the user isn't blocked and nothing double-counts on retry since there's no retry, just "next real completion resumes from whatever's actually stored."
- Batched write is all-or-nothing at the Firestore level, so there's no partial-desync failure mode to handle explicitly.

## 8. Testing

- Unit tests (Swift Testing, no Firebase): `StreakCalculatorTests` (consecutive day, gap with freeze, gap without freeze, freeze accrual at 7/14/21, cap at 3, same-day idempotency), `LevelCalculatorTests` (mid-ladder, exactly-at-threshold, above ceiling), `AchievementEngineTests` (one test per `criterion.kind`, plus one confirming `.unbuildable` always renders locked with no progress regardless of stats).
- Existing `ModelDecodingTests`/`RepositoryTests` updated for the new bundled fallback files (`achievement_catalog.json` replacing `achievements.json`, `profile.json` unchanged in shape).
- Manual: verify a full completion round-trip (streak increments, XP/level updates, an achievement actually flips to earned) against the real seeded project once deployed — same manual-verification pattern as sub-project 4 §8.

## 9. Open implementation decisions (flagged, not blocking)

- Exact `criterion.topic` string values for the 6 topic-mastery achievements — picked in the implementation plan by reading current `scripts/seed-questions.json` topic strings directly, not guessed here.
- `memberSinceDisplay` (`UserProfile`) formats from the existing `users/{uid}.createdAt` (`FieldValue.serverTimestamp()`, already written by `AuthRepository.ensureUserDocument`) — no new field needed.
