# Leaderboard (Global, All-Time) — Design

Sub-project 3 of 6 in the backend build-out (see `docs/superpowers/specs/2026-09-08-firebase-auth-setup-design.md` §0). Sub-projects 1 (Auth), 2 (Profile/XP/streak sync), and 4 (Remote question bank — done as the `dailyQuizzes` shared-edition system, superseding that sub-project's original per-user-seeded design) are done and merged. Cross-reference: `requirements.md` §2.2 (Gamification System): "Global and friends-based leaderboards (weekly + all-time), ranked by XP; optional opt-out for privacy."

## 0. Scope decomposition

`requirements.md` §2.2 describes three independent pieces: **global** ranking, **weekly** ranking (needs a resetting counter separate from lifetime XP), and **friends** ranking (needs a social graph — requests/accepts/discovery — that doesn't exist anywhere in this app). None of those three shares much beyond "sort people by an XP number," and weekly/friends each need their own real design (a reset mechanism with no Cloud Functions infra yet; a friend-relationship data model). Building all three in one pass would be too large for one spec.

**This pass covers global, all-time only.** Weekly ranking and friends ranking, and the "optional opt-out for privacy" from requirements.md §2.2, are explicitly deferred to later sub-projects — not designed here. The current screen's "Friends"/"Global" and "Week"/"All time" pickers, which today sit over static mock data and don't actually do anything, are removed rather than left as dead toggles promising features that don't exist yet.

## 1. Goal

Replace `LeaderboardRepository`'s fully-static bundled mock data (`leaderboard.json` — 8 fake entries including a fake "you" row with a hardcoded XP number) with a real global ranking over every user's actual `totalXP` (sub-project 2), rendered against the live signed-in user.

Out of scope for this pass: weekly leaderboard, friends leaderboard, privacy opt-out toggle (all deferred, §0), push/analytics (sub-projects 5, 6).

## 2. Firestore schema

**New top-level collection `leaderboardEntries/{uid}`** — a minimal public mirror of exactly what's safe to show every other signed-in user, deliberately not the private `users/{uid}` doc (which holds email, answer history, achievement timestamps, etc.):

```
{
  displayName: string   // same fallback as ProfileRepository.buildProfile: "SwiftUp user" if empty/nil
  totalXP: number
  updatedAt: Timestamp  // FieldValue.serverTimestamp()
}
```

`level` is intentionally not stored — it's derived client-side from `totalXP` via the existing `LevelCalculator`, the same as every other screen that shows a level, so there's exactly one place that maps XP to level.

**Firestore rules** — read-open to any signed-in user, write-restricted to the owner (same shape as `users/{uid}`'s owner rule, but with public read instead of owner-only read):

```
match /leaderboardEntries/{uid} {
  allow read: if request.auth != null;
  allow write: if request.auth != null && request.auth.uid == uid;
}
```

## 3. Write path

No new write call site. `ProfileRepository.recordCompletion(_:for:)` (sub-project 2) already batches a write to `users/{uid}` with the freshly computed `newTotalXP` every time a user finishes a day's quiz. This pass adds one more operation to that same `WriteBatch`:

```swift
let leaderboardRef = Firestore.firestore().collection("leaderboardEntries").document(uid)
batch.setData([
    "displayName": displayName,       // same fallback rule as buildProfile's `name`, computed
                                       // before the batch instead of after (buildProfile currently
                                       // runs post-commit) so both writes see the same value
    "totalXP": newTotalXP,
    "updatedAt": FieldValue.serverTimestamp(),
], forDocument: leaderboardRef, merge: true)
```
`recordCompletion` currently calls `Self.buildProfile(displayName: snapshot.get("displayName") as? String, ...)` *after* `batch.commit()` (it only needs the fallback name for the in-memory `profile` it sets locally). This pass hoists that one-line fallback (`(displayName?.isEmpty == false) ? displayName! : "SwiftUp user"`) above the batch construction so the same computed string feeds both the batch write and the existing post-commit `buildProfile` call — no behavior change to `buildProfile` itself, just reusing its existing fallback rule slightly earlier.

Same atomicity and non-blocking-on-failure behavior as the rest of that batch (sub-project 2 §5, §7) — no new failure mode. A user who has never completed a quiz simply has no `leaderboardEntries` doc yet, which is correct: there's no XP to rank.

## 4. Read path — ranking at scale

Two independent reads, both cheap regardless of total user count — no Cloud Function, no denormalized rank cache to keep in sync:

**Top of the board:**
```swift
Firestore.firestore().collection("leaderboardEntries")
    .order(by: "totalXP", descending: true)
    .limit(to: 50)
```
Single-field index, auto-created by Firestore. Rank within this page is just the array index + 1.

**Current user's rank and percentile** (used whether or not they're in the top 50), via Firestore's server-side COUNT aggregation (`AggregateQuery.count`, billed by index entries scanned, not full document reads):
```swift
let ahead = try await db.collection("leaderboardEntries")
    .whereField("totalXP", isGreaterThan: myXP)
    .count.getAggregation(source: .server)
let total = try await db.collection("leaderboardEntries")
    .count.getAggregation(source: .server)
// rank = ahead.count + 1; percentile = rank / total.count
```
Users tied on `totalXP` get the same rank number (standard leaderboard behavior — a strict `>` count doesn't distinguish ties). If the current user has no `leaderboardEntries` doc yet (never completed a quiz), rank/percentile are simply not computed — the UI shows an unranked state (§5) instead of a bogus "rank 1."

## 5. Client architecture & UI

**`LeaderboardEntry`** (`SwiftUp/Models/LeaderboardEntry.swift`) — rewritten from the mock shape to:
```swift
struct LeaderboardEntry: Identifiable {
    let uid: String
    var id: String { uid }
    let displayName: String
    let totalXP: Int
    let rank: Int
}
```
`isCurrentUser` is dropped as stored state — views compare `entry.uid == authRepo.currentUser?.uid` directly. `level` is not stored on the entry; it's computed per-row at render time via `LevelCalculator.level(for: entry.totalXP, ladder:)`, with `LeaderboardRepository` loading its own bundled `levels.json` copy in `init` — matching the existing per-repository-owns-its-bundled-resources convention (`ProfileRepository`, `QuestionRepository` each do the same rather than sharing a dependency).

**`LeaderboardRepository`** — rewritten to the same async/`@Observable` shape as `QuestionRepository`/`ProfileRepository`:
```swift
@Observable
final class LeaderboardRepository {
    private(set) var topEntries: [LeaderboardEntry] = []
    private(set) var myRank: (rank: Int, percentile: Int)?   // nil if not yet ranked
    private(set) var isLoading = false
    let levels: [LevelInfo]

    init(bundle: Bundle = .main) { levels = ...; }             // no Firebase touch
    static func preview(bundle: Bundle = .main) -> LeaderboardRepository   // bundled fallback, never touches Firestore
    func load(for uid: String) async { ... }                   // top-50 query + rank/percentile aggregates
}
```
`load(for:)` builds `topEntries` by decoding the top-50 query's documents (`displayName`, `totalXP`) and zipping each with its 1-based position in that already-`totalXP`-descending result (`enumerated()` — `rank = offset + 1`) — `rank` isn't a stored Firestore field, it only exists as this page's position.
`leaderboard.json`'s existing mock content becomes the bundled **fallback-only** payload (`preview()`, and `load(for:)`'s failure path with nothing cached) — same demotion pattern sub-project 2 applied to `profile.json`/`topics.json`, never deleted, just no longer live data.

`RootView` changes `leaderboardRepository` from `private let` to `@State private var` (it's now mutated post-init, same reasoning as `questionRepository`/`profileRepository`).

**`LeaderboardView`** — `load(for:)` is triggered from this view's own `.task` (needs `@Environment(AuthRepository.self)` added, same pattern as `TodayFlowView`), not eagerly at app launch — the board isn't needed until the user actually opens this tab.

UI changes:
- The "Friends"/"Global" and "Week"/"All time" `SegmentedPicker`s are removed (§0 — no dead toggles for unbuilt features).
- Masthead `RuledMasthead(left: "Week 36", right: "Closes Sunday 24:00")` → reflects an all-time board instead (e.g. `left: "All-time"`, `right: "Top 50"`) — exact copy is an implementation-time wording choice, not a design decision.
- The "Scored on xp earned this week only…" footer blurb is rewritten to describe all-time XP scoring instead of weekly.
- The "Listed because leaderboards are on in settings…" opt-out line is removed — no opt-out exists this pass (§0); reintroduced when that sub-project lands.
- "Top 4% globally" becomes the real computed percentile from `myRank`.
- If the current user isn't in `topEntries` (outside top 50), their own row is pinned below the list using `myRank`; if `myRank` is `nil` (no completions yet), that row is replaced with a short prompt to finish today's five instead of a fabricated rank.

## 6. Error handling

- `load(for:)` Firestore failure with a warm SDK cache: served transparently (same as sub-projects 2/4).
- Failure with no cache (offline, first launch): falls back to bundled `leaderboard.json`; `myRank` stays `nil` in this path (the mock data has no meaningful relationship to the signed-in user's real XP).
- Write failure in `recordCompletion`'s batch: same non-blocking behavior as the rest of that batch (sub-project 2 §7) — worst case one day's leaderboard update is missed, corrected by the next completion.

## 7. Testing

- Unit tests (Swift Testing, no Firebase): rank/percentile arithmetic (`rank = aheadCount + 1`, `percentile = rank / total`) as a small pure function extracted for testability; `LevelCalculator` lookups reused from sub-project 2's existing coverage, not retested here.
- `RepositoryTests` updated for `LeaderboardRepository.preview()`'s new shape (`topEntries` instead of `entries`).
- The actual Firestore query/aggregation logic isn't unit-testable (no emulator in this project) — same as every other repository's `load(for:)` today. Verified by manual run-through against the real project once deployed, with at least two seeded accounts at different XP totals to confirm ordering and rank/percentile both read correctly.

## 8. Open implementation decisions (flagged, not blocking)

- Exact masthead/footer copy wording (§5) — picked in the implementation plan, not itemized here.
- Whether `limit(to: 50)` is the right top-N size — 50 is a reasonable default for a first pass; trivial to change later since it's just the `limit()` argument, not a schema decision.
