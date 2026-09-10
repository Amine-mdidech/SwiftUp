# Leaderboard (Global, All-Time) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `LeaderboardRepository`'s fully-static mock data (`leaderboard.json` — 8 fake entries including a fake "you" with a hardcoded XP number) with a real global, all-time ranking over every user's actual `totalXP`.

**Architecture:** A new public-but-minimal Firestore collection, `leaderboardEntries/{uid}`, mirrors just `displayName`/`totalXP` out of the private `users/{uid}` doc — written by `ProfileRepository.recordCompletion`'s existing batch, the same write path already responsible for XP. `LeaderboardRepository` becomes async/`@Observable`: a top-50 query for the board, plus two Firestore COUNT aggregation queries (no Cloud Function, no denormalized rank cache) for the signed-in user's own rank/percentile. Rank/percentile arithmetic and top-N ordering are pure functions (`LeaderboardRanking`), mirroring how `QuestionSelector`/`LevelCalculator`/`StreakCalculator` keep logic Firebase-free and unit-testable.

**Tech Stack:** SwiftUI, Swift Testing, FirebaseFirestore (already a dependency, including COUNT aggregation support at the project's `from: 11.0.0` floor).

**Spec:** `docs/superpowers/specs/2026-09-10-leaderboard-design.md`

## Global Constraints

- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), never XCTest.
- `SwiftUp.xcodeproj/` is gitignored — run `xcodegen generate` after adding any new file, before building.
- A repository that owns live/loaded state (not just a static bundle decode) must be held as `@State private var`, not `let`, wherever a View owns one (established `RootView` convention).
- Never touch Firebase in a repository's `init` — only in explicitly-invoked async methods (established `AuthRepository`/`QuestionRepository`/`ProfileRepository` pattern), so `#Preview` stays safe.
- Bundled JSON is demoted to **fallback-only** content (`.preview()`, and `load(for:)`'s failure path), never deleted — matches `questions.json`/`profile.json`'s existing role.
- `leaderboardEntries/{uid}` stores only `displayName`, `totalXP`, `updatedAt` — never anything from the private `users/{uid}` doc (no email, no achievement/answer history, no skill level). This is the whole reason the collection exists separately.
- No opt-out toggle, no weekly tracking, no friends graph this pass (spec §0) — the "Friends"/"Global" and "Week"/"All time" pickers are removed, not stubbed.

---

## Task 1: `LeaderboardRecord` model + `LeaderboardRanking` (pure ranking/percentile logic)

**Files:**
- Create: `SwiftUp/Models/LeaderboardRecord.swift`
- Create: `SwiftUp/Data/LeaderboardRanking.swift`
- Test: `SwiftUpTests/LeaderboardRankingTests.swift`

This task is purely additive — it doesn't touch `LeaderboardEntry`, `LeaderboardRepository`, or `LeaderboardView`, so the project keeps building and every existing test keeps passing throughout.

**Interfaces:**
- Produces (used by Task 4):
  - `struct LeaderboardRecord: Codable { let uid: String; let displayName: String; let totalXP: Int }`
  - `enum LeaderboardRanking { struct RankedRecord { let uid: String; let displayName: String; let totalXP: Int; let rank: Int }; static func rankedRecords(from records: [LeaderboardRecord]) -> [RankedRecord]; static func rank(aheadCount: Int, totalCount: Int) -> (rank: Int, percentile: Int)? }`

- [ ] **Step 1: Write the failing tests**

Create `SwiftUpTests/LeaderboardRankingTests.swift`:

```swift
import Testing
@testable import SwiftUp

struct LeaderboardRankingTests {
    @Test func rankedRecordsSortsDescendingByXPAndAssigns1BasedRank() {
        let records = [
            LeaderboardRecord(uid: "a", displayName: "A", totalXP: 100),
            LeaderboardRecord(uid: "b", displayName: "B", totalXP: 300),
            LeaderboardRecord(uid: "c", displayName: "C", totalXP: 200),
        ]
        let ranked = LeaderboardRanking.rankedRecords(from: records)
        #expect(ranked.map(\.uid) == ["b", "c", "a"])
        #expect(ranked.map(\.rank) == [1, 2, 3])
    }

    @Test func rankFromCountsComputesRankAndPercentile() {
        let result = LeaderboardRanking.rank(aheadCount: 4, totalCount: 100)
        #expect(result?.rank == 5)
        #expect(result?.percentile == 5)
    }

    @Test func rankFromCountsRoundsPercentileUpSoTopSpotIsNeverZeroPercent() {
        let result = LeaderboardRanking.rank(aheadCount: 0, totalCount: 1_000_000)
        #expect(result?.rank == 1)
        #expect(result?.percentile == 1)
    }

    @Test func rankFromCountsIsNilWithNoRankedUsers() {
        #expect(LeaderboardRanking.rank(aheadCount: 0, totalCount: 0) == nil)
    }

    @Test func tiedXPGetsTheSameRankNumber() {
        // Two users both with 3 users strictly ahead of them -> both rank 4, regardless of
        // however many others share their exact XP (a strict `>` count can't tell them apart).
        let a = LeaderboardRanking.rank(aheadCount: 3, totalCount: 10)
        let b = LeaderboardRanking.rank(aheadCount: 3, totalCount: 10)
        #expect(a?.rank == b?.rank)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
xcodegen generate
xcodebuild test -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SwiftUpTests/LeaderboardRankingTests
```
Expected: FAIL — `LeaderboardRecord`/`LeaderboardRanking` don't exist yet.

- [ ] **Step 3: Implement**

Create `SwiftUp/Models/LeaderboardRecord.swift`:

```swift
import Foundation

/// A minimal public record — decoded either from a `leaderboardEntries/{uid}` Firestore document
/// (where `uid` is filled in from the document ID, not stored as a field) or from the bundled
/// offline-fallback JSON (`leaderboard.json`, where `uid` is an explicit field since there's no
/// document ID to borrow it from).
struct LeaderboardRecord: Codable {
    let uid: String
    let displayName: String
    let totalXP: Int
}
```

Create `SwiftUp/Data/LeaderboardRanking.swift`:

```swift
import Foundation

enum LeaderboardRanking {
    /// A ranked position, deliberately decoupled from any UI-facing model — `LeaderboardRepository`
    /// (which does touch Firestore) maps this 1:1 into `LeaderboardEntry` for the view layer.
    struct RankedRecord {
        let uid: String
        let displayName: String
        let totalXP: Int
        let rank: Int
    }

    /// Assigns 1-based rank by totalXP descending, over whatever page of records is passed in
    /// (e.g. a top-50 query result) — ties share adjacent rank numbers purely by sort position
    /// here. `rank(aheadCount:totalCount:)` below is what gives a single user (who might not be
    /// on this page at all) a rank that correctly ties with everyone else on exact XP.
    static func rankedRecords(from records: [LeaderboardRecord]) -> [RankedRecord] {
        records.sorted { $0.totalXP > $1.totalXP }.enumerated().map { offset, record in
            RankedRecord(uid: record.uid, displayName: record.displayName, totalXP: record.totalXP, rank: offset + 1)
        }
    }

    /// The current user's rank/percentile from two counts: how many users have strictly more XP
    /// (`aheadCount`), and how many users exist in total (`totalCount`, includes the current
    /// user). Ties on XP share the same rank number since a strict `>` count can't distinguish
    /// them — standard leaderboard behavior. `nil` when there's nobody ranked at all.
    static func rank(aheadCount: Int, totalCount: Int) -> (rank: Int, percentile: Int)? {
        guard totalCount > 0 else { return nil }
        let rank = aheadCount + 1
        let percentile = Int((Double(rank) / Double(totalCount) * 100).rounded(.up))
        return (rank: rank, percentile: percentile)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Same command as Step 2. Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/Models/LeaderboardRecord.swift SwiftUp/Data/LeaderboardRanking.swift SwiftUpTests/LeaderboardRankingTests.swift
git commit -m "$(cat <<'EOF'
Add LeaderboardRecord + LeaderboardRanking: pure rank/percentile math

Decoupled from the UI-facing LeaderboardEntry model (rewritten in a
later commit) so this logic is unit-testable without Firestore.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GpSXYkWsf7vU18a4x1P6p7
EOF
)"
```

---

## Task 2: Firestore schema + rules for `leaderboardEntries`

**Files:**
- Modify: `firestore.rules`

**Interfaces:** None (infrastructure only).

- [ ] **Step 1: Add the collection rule**

In `firestore.rules`, add a new top-level `match` block alongside the existing `questions` one. The full file becomes:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
      match /dailyCompletions/{date} {
        allow read, write: if request.auth != null && request.auth.uid == uid;
      }
    }
    match /questions/{questionId} {
      allow read: if request.auth != null;
      allow write: if false;
    }
    match /dailyQuizzes/{date} {
      allow read: if request.auth != null;
      allow write: if false;
    }
    match /leaderboardEntries/{uid} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

- [ ] **Step 2: Deploy the updated rules**

The Firebase CLI is already installed and authenticated against this project (`swiftup-9eee9`, linked via `.firebaserc`/`firebase.json`).

Run:
```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
firebase deploy --only firestore:rules
```
Expected: `✔ Deploy complete!` — a `cloud.firestore: rules file firestore.rules compiled successfully` line confirms the new rule parsed correctly.

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "$(cat <<'EOF'
Add Firestore rule for leaderboardEntries: public read, owner write

A minimal public mirror of a user's displayName/totalXP for the
global leaderboard — deliberately not the private users/{uid} doc.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GpSXYkWsf7vU18a4x1P6p7
EOF
)"
```

---

## Task 3: `ProfileRepository.recordCompletion` writes the public leaderboard record

**Files:**
- Modify: `SwiftUp/Data/ProfileRepository.swift:80-171` (`recordCompletion`)

**Interfaces:**
- Consumes: nothing new (uses the existing `snapshot`/`batch`/`newTotalXP` already computed in this method).
- No new public interface — `recordCompletion`'s signature is unchanged.

- [ ] **Step 1: Hoist the display-name fallback above the batch, and add the leaderboard write to it**

In `SwiftUp/Data/ProfileRepository.swift`, `recordCompletion` currently reads (lines 100-158):

```swift
            let previousStreak = (snapshot.get("streakDays") as? Int) ?? 0
            let previousFreezes = (snapshot.get("freezesAvailable") as? Int) ?? 0
            let previousLastCompleted = snapshot.get("lastCompletedDate") as? String
            let streakResult = StreakCalculator.apply(
                lastCompletedDate: previousLastCompleted, streakDays: previousStreak,
                freezesAvailable: previousFreezes, today: today
            )
```
...
```swift
            let batch = Firestore.firestore().batch()
            batch.setData(userUpdates, forDocument: userRef, merge: true)
            let dayRef = userRef.collection("dailyCompletions").document(today)
            batch.setData(["correctCount": session.correctCount, "xpEarned": session.totalXPEarned], forDocument: dayRef)
            try await batch.commit()

            let freezesAvailable = streakResult.freezesAvailable
            profile = Self.buildProfile(
                displayName: snapshot.get("displayName") as? String,
                createdAt: snapshot.get("createdAt") as? Timestamp,
                freezesAvailable: freezesAvailable, stats: stats, level: level
            )
```

Change the first block to also compute the resolved display name (same fallback rule `buildProfile` already applies internally — computed once here so both the new leaderboard write and the existing `buildProfile` call below use the identical value):

```swift
            let previousStreak = (snapshot.get("streakDays") as? Int) ?? 0
            let previousFreezes = (snapshot.get("freezesAvailable") as? Int) ?? 0
            let previousLastCompleted = snapshot.get("lastCompletedDate") as? String
            let streakResult = StreakCalculator.apply(
                lastCompletedDate: previousLastCompleted, streakDays: previousStreak,
                freezesAvailable: previousFreezes, today: today
            )

            let rawDisplayName = snapshot.get("displayName") as? String
            let displayName = (rawDisplayName?.isEmpty == false) ? rawDisplayName! : "SwiftUp user"
```

Change the batch block to add the third write and reuse `displayName`:

```swift
            let batch = Firestore.firestore().batch()
            batch.setData(userUpdates, forDocument: userRef, merge: true)
            let dayRef = userRef.collection("dailyCompletions").document(today)
            batch.setData(["correctCount": session.correctCount, "xpEarned": session.totalXPEarned], forDocument: dayRef)
            let leaderboardRef = Firestore.firestore().collection("leaderboardEntries").document(uid)
            batch.setData([
                "displayName": displayName,
                "totalXP": newTotalXP,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocument: leaderboardRef, merge: true)
            try await batch.commit()

            let freezesAvailable = streakResult.freezesAvailable
            profile = Self.buildProfile(
                displayName: displayName,
                createdAt: snapshot.get("createdAt") as? Timestamp,
                freezesAvailable: freezesAvailable, stats: stats, level: level
            )
```

- [ ] **Step 2: Verify it builds and existing tests still pass**

```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
xcodegen generate
xcodebuild test -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: build succeeds, all existing tests still PASS (this change has no unit test of its own — `recordCompletion`'s Firestore calls aren't unit-tested anywhere in this project, same as before; it's verified by the manual completion round-trip in Task 4's final step).

- [ ] **Step 3: Commit**

```bash
git add SwiftUp/Data/ProfileRepository.swift
git commit -m "$(cat <<'EOF'
Write a public leaderboardEntries record on every quiz completion

Piggybacks on recordCompletion's existing batch write — same
atomicity and non-blocking-on-failure behavior as the rest of it.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GpSXYkWsf7vU18a4x1P6p7
EOF
)"
```

---

## Task 4: `LeaderboardEntry`/`LeaderboardRepository`/`LeaderboardView` rewrite

**Files:**
- Modify: `SwiftUp/Models/LeaderboardEntry.swift` (full rewrite)
- Modify: `SwiftUp/Data/LeaderboardRepository.swift` (full rewrite)
- Modify: `SwiftUp/Resources/leaderboard.json` (full rewrite)
- Modify: `SwiftUpTests/Fixtures/leaderboard.json` (identical copy of the above)
- Modify: `SwiftUp/Features/Leaderboard/LeaderboardView.swift` (full rewrite)
- Modify: `SwiftUp/App/RootView.swift:10` (`let` → `@State var`)
- Modify: `SwiftUp/App/MainTabView.swift:33` (`#Preview` only)
- Modify: `SwiftUpTests/RepositoryTests.swift:35-39`

**Interfaces:**
- Consumes: `LeaderboardRecord`, `LeaderboardRanking` (Task 1); `LevelCalculator`, `LevelInfo` (existing); `AuthRepository.currentUser` (existing).
- Produces:
  - `struct LeaderboardEntry: Identifiable { let uid: String; var id: String { uid }; let displayName: String; let totalXP: Int; let rank: Int }`
  - `@Observable final class LeaderboardRepository { let levels: [LevelInfo]; private(set) var topEntries: [LeaderboardEntry]; private(set) var myEntry: LeaderboardEntry?; private(set) var myPercentile: Int?; private(set) var totalRanked: Int; private(set) var isLoading: Bool; init(bundle: Bundle = .main); static func preview(bundle: Bundle = .main) -> LeaderboardRepository; func load(for uid: String) async }`

- [ ] **Step 1: Rewrite the model**

Replace `SwiftUp/Models/LeaderboardEntry.swift` entirely:

```swift
import Foundation

struct LeaderboardEntry: Identifiable {
    let uid: String
    var id: String { uid }
    let displayName: String
    let totalXP: Int
    let rank: Int
}
```

- [ ] **Step 2: Rewrite the bundled fallback data**

Replace `SwiftUp/Resources/leaderboard.json` entirely:

```json
[
  {"uid": "u1", "displayName": "Dana Okafor", "totalXP": 640},
  {"uid": "u2", "displayName": "Tomas Lind", "totalXP": 505},
  {"uid": "preview-user", "displayName": "Preview User", "totalXP": 385},
  {"uid": "u4", "displayName": "Priya Raman", "totalXP": 370},
  {"uid": "u5", "displayName": "Sam Whitfield", "totalXP": 310},
  {"uid": "u6", "displayName": "Jo Mensah", "totalXP": 240},
  {"uid": "u7", "displayName": "Elif Kaya", "totalXP": 180},
  {"uid": "u8", "displayName": "Ana Sorescu", "totalXP": 95}
]
```
(`"preview-user"` matches the uid `AuthRepository(isPreview: true, signedIn: true)` uses, so SwiftUI Previews render that row highlighted as "you".)

```bash
cp "SwiftUp/Resources/leaderboard.json" "SwiftUpTests/Fixtures/leaderboard.json"
```

- [ ] **Step 3: Rewrite the repository**

Replace `SwiftUp/Data/LeaderboardRepository.swift` entirely:

```swift
import Foundation
import FirebaseFirestore

@Observable
final class LeaderboardRepository {
    let levels: [LevelInfo]
    private(set) var topEntries: [LeaderboardEntry] = []
    /// The signed-in user's own ranked entry — `nil` until they've completed at least one daily
    /// quiz (no `leaderboardEntries` doc yet), or if that lookup itself failed.
    private(set) var myEntry: LeaderboardEntry?
    private(set) var myPercentile: Int?
    private(set) var totalRanked = 0
    private(set) var isLoading = false

    init(bundle: Bundle = .main) {
        levels = decodeJSONResource([LevelInfo].self, filename: "levels", bundle: bundle) ?? []
    }

    /// Synchronously loads bundled fallback content — safe for #Preview, never touches Firestore.
    static func preview(bundle: Bundle = .main) -> LeaderboardRepository {
        let repo = LeaderboardRepository(bundle: bundle)
        repo.applyBundledFallback(bundle: bundle)
        return repo
    }

    private func applyBundledFallback(bundle: Bundle) {
        let records = decodeJSONResource([LeaderboardRecord].self, filename: "leaderboard", bundle: bundle) ?? []
        topEntries = Self.entries(from: LeaderboardRanking.rankedRecords(from: records))
        myEntry = nil
        myPercentile = nil
        totalRanked = topEntries.count
    }

    /// Fetches the real global, all-time board: the top 50 by totalXP, plus the signed-in user's
    /// own rank/percentile via COUNT aggregation (whether or not they're in the top 50). Falls
    /// back to the bundled set only if the top-50 fetch itself is unreachable; a failure fetching
    /// just the user's own rank leaves the real top-50 in place with `myEntry` simply unset.
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        let entriesRef = Firestore.firestore().collection("leaderboardEntries")

        do {
            let snapshot = try await entriesRef
                .order(by: "totalXP", descending: true)
                .limit(to: 50)
                .getDocuments()
            let records: [LeaderboardRecord] = snapshot.documents.compactMap { doc in
                guard let displayName = doc.get("displayName") as? String, let totalXP = doc.get("totalXP") as? Int else {
                    return nil
                }
                return LeaderboardRecord(uid: doc.documentID, displayName: displayName, totalXP: totalXP)
            }
            topEntries = Self.entries(from: LeaderboardRanking.rankedRecords(from: records))
        } catch {
            applyBundledFallback(bundle: .main)
            return
        }

        myEntry = nil
        myPercentile = nil
        guard
            let mySnapshot = try? await entriesRef.document(uid).getDocument(),
            let myDisplayName = mySnapshot.get("displayName") as? String,
            let myXP = mySnapshot.get("totalXP") as? Int
        else { return }

        guard
            let ahead = try? await entriesRef.whereField("totalXP", isGreaterThan: myXP).count.getAggregation(source: .server),
            let total = try? await entriesRef.count.getAggregation(source: .server)
        else { return }

        totalRanked = Int(truncating: total.count)
        guard let result = LeaderboardRanking.rank(aheadCount: Int(truncating: ahead.count), totalCount: totalRanked) else { return }
        myEntry = LeaderboardEntry(uid: uid, displayName: myDisplayName, totalXP: myXP, rank: result.rank)
        myPercentile = result.percentile
    }

    private static func entries(from ranked: [LeaderboardRanking.RankedRecord]) -> [LeaderboardEntry] {
        ranked.map { LeaderboardEntry(uid: $0.uid, displayName: $0.displayName, totalXP: $0.totalXP, rank: $0.rank) }
    }
}
```

- [ ] **Step 4: Rewrite the view**

Replace `SwiftUp/Features/Leaderboard/LeaderboardView.swift` entirely:

```swift
import SwiftUI

struct LeaderboardView: View {
    @Environment(LeaderboardRepository.self) private var repo
    @Environment(AuthRepository.self) private var authRepo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: "All-time", right: "Ranked by total xp")

                Text("Standings").font(Theme.Fonts.heading(32)).padding(.top, 22)

                VStack(spacing: 0) {
                    ForEach(repo.topEntries) { entry in
                        entryRow(entry, isCurrentUser: entry.uid == authRepo.currentUser?.uid)
                    }
                    if let myEntry = repo.myEntry, !repo.topEntries.contains(where: { $0.uid == myEntry.uid }) {
                        entryRow(myEntry, isCurrentUser: true)
                    }
                }
                .padding(.top, 24)

                if repo.myEntry == nil && !repo.isLoading {
                    Text("Finish today's five to join the leaderboard.")
                        .font(Theme.Fonts.body(13)).foregroundStyle(Theme.Colors.neutral800)
                        .padding(.top, 18)
                }

                Text("Scored on total xp earned — every correct answer, plus a 25 xp bonus for a perfect five.")
                    .font(Theme.Fonts.body(13)).foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 18)

                if let myEntry = repo.myEntry, let myPercentile = repo.myPercentile {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            EyebrowLabel("Rank #\(myEntry.rank)")
                            Text("out of \(repo.totalRanked) ranked").font(.system(size: 13)).foregroundStyle(Theme.Colors.neutral800)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            EyebrowLabel("Top \(myPercentile)%")
                            Text("globally").font(.system(size: 13)).foregroundStyle(Theme.Colors.neutral800)
                        }
                    }
                    .padding(.top, 22)
                    .padding(.top, 14)
                    .overlay(Rectangle().fill(Theme.Colors.text).frame(height: 1), alignment: .top)
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
        .task {
            guard let uid = authRepo.currentUser?.uid else { return }
            await repo.load(for: uid)
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: LeaderboardEntry, isCurrentUser: Bool) -> some View {
        let level = LevelCalculator.level(for: entry.totalXP, ladder: repo.levels)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(entry.rank)")
                .font(Theme.Fonts.heading(isCurrentUser ? 17 : 15))
                .foregroundStyle(isCurrentUser ? Theme.Colors.accent700 : Theme.Colors.text)
                .frame(width: 26, alignment: .leading)
            Text(entry.displayName)
                .font(isCurrentUser ? Theme.Fonts.heading(16) : Theme.Fonts.body(15))
            Spacer()
            EyebrowLabel("L\(level.number)", color: isCurrentUser ? Theme.Colors.accent700 : Theme.Colors.neutral700)
            Text("\(entry.totalXP)")
                .font(Theme.Fonts.heading(isCurrentUser ? 18 : 15))
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, isCurrentUser ? 14 : 11)
        .padding(.horizontal, isCurrentUser ? 10 : 0)
        .background(isCurrentUser ? Theme.Colors.accent100 : Color.clear)
        .overlay(alignment: .leading) {
            if isCurrentUser {
                Rectangle().fill(Theme.Colors.accent).frame(width: 3)
            }
        }
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
    }
}

#Preview {
    NavigationStack { LeaderboardView() }
        .environment(LeaderboardRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
```

- [ ] **Step 5: Update `RootView` to hold the repository as mutable state**

In `SwiftUp/App/RootView.swift:10`, change:
```swift
    private let leaderboardRepository = LeaderboardRepository()
```
to:
```swift
    @State private var leaderboardRepository = LeaderboardRepository()
```

- [ ] **Step 6: Fix `MainTabView`'s preview**

In `SwiftUp/App/MainTabView.swift:33`, change:
```swift
        .environment(LeaderboardRepository())
```
to:
```swift
        .environment(LeaderboardRepository.preview())
```

- [ ] **Step 7: Update the repository test**

In `SwiftUpTests/RepositoryTests.swift`, replace (lines 35-39):
```swift
    @Test func leaderboardRepositoryLoadsEntriesSortedByRank() {
        let repo = LeaderboardRepository(bundle: testBundle)
        #expect(repo.entries.count == 8)
        #expect(repo.entries.first?.rank == 1)
    }
```
with:
```swift
    @Test func leaderboardRepositoryPreviewLoadsEntriesSortedByRank() {
        let repo = LeaderboardRepository.preview(bundle: testBundle)
        #expect(repo.topEntries.count == 8)
        #expect(repo.topEntries.first?.rank == 1)
        #expect(repo.topEntries.first?.totalXP == 640)
    }
```

- [ ] **Step 8: Verify everything builds and all tests pass**

```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
xcodegen generate
xcodebuild test -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: build succeeds, every test PASSes (including Task 1's `LeaderboardRankingTests` and this task's updated `RepositoryTests`).

- [ ] **Step 9: Commit**

```bash
git add SwiftUp/Models/LeaderboardEntry.swift SwiftUp/Data/LeaderboardRepository.swift \
  SwiftUp/Resources/leaderboard.json SwiftUpTests/Fixtures/leaderboard.json \
  SwiftUp/Features/Leaderboard/LeaderboardView.swift SwiftUp/App/RootView.swift \
  SwiftUp/App/MainTabView.swift SwiftUpTests/RepositoryTests.swift
git commit -m "$(cat <<'EOF'
Replace mocked leaderboard with a real global all-time ranking

LeaderboardRepository now reads leaderboardEntries: a top-50 query
for the board plus two COUNT aggregations for the signed-in user's
own rank/percentile, whether or not they're in the top 50. Removes
the inert Friends/Global and Week/All-time pickers along with the
copy that referenced features that don't exist (weekly scoring, a
leaderboard privacy toggle) — this pass is global, all-time only.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GpSXYkWsf7vU18a4x1P6p7
EOF
)"
```

- [ ] **Step 10: Manual verification**

No Firestore emulator exists in this project, so the query/aggregation logic itself isn't covered by an automated test — verify it against the real, already-deployed project:

1. Run the app on two different signed-in accounts (or one account, completing a quiz, checking the board, then completing another day on a second account) so at least two `leaderboardEntries` docs exist with different `totalXP`.
2. Open the Leaderboard tab on each account and confirm: the board is ordered highest-XP-first, each account's own row highlights correctly, and "Rank #N · out of M ranked · Top X%" matches manual arithmetic against how many accounts exist and their relative XP.
3. Confirm a brand-new account (no completed quiz yet) sees "Finish today's five to join the leaderboard." instead of a fabricated rank.
