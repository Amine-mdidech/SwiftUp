# Profile/XP/Streak Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `ProfileRepository`'s fully-static mock data (name "Maya Reyes", fixed XP/streak/topics/achievements) with real per-user Firestore-backed identity, XP/level, a streak-with-freeze mechanic, dynamic per-topic accuracy, and computed achievement unlocking — driven by actual daily-quiz completions.

**Architecture:** Three pure, Firebase-free engines (`LevelCalculator`, `StreakCalculator`, `AchievementEngine`) compute derived state from stored Firestore fields, mirroring how `QuestionSelector` works in sub-project 4. `ProfileRepository` becomes async/`@Observable`, reading `users/{uid}` (extended with XP/streak/topic-stats fields) plus a new `users/{uid}/dailyCompletions/{date}` subcollection, and writing both on quiz completion via `TodayFlowView.finish()` — the same completion hook sub-project 4 already established. The achievement catalog (title/detail/xpReward/unlock-criterion) moves to bundled static JSON; per-user status/progress is computed at load/completion time, never stored as flat status strings.

**Tech Stack:** SwiftUI, Swift Testing, FirebaseFirestore (already a dependency).

**Spec:** `docs/superpowers/specs/2026-09-09-profile-xp-streak-sync-design.md`

## Global Constraints

- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), never XCTest.
- `SwiftUp.xcodeproj/` is gitignored — `project.yml` is the source of truth; no changes needed this plan (`FirebaseFirestore` is already a target dependency, and both `SwiftUp/Resources/` and `SwiftUpTests/Fixtures/` are whole-folder source paths, so new bundled JSON files are picked up automatically by `xcodegen generate`).
- Any Firebase-touching repository method must be safe to call from a `#Preview` — never touch Firebase in `init`, only in explicitly-invoked async methods (established `AuthRepository`/`QuestionRepository` pattern).
- A repository that owns live/loaded state (not just a static bundle decode) must be held as `@State private var`, not `let`, wherever a View owns one (established from `RootView`'s `questionRepository`/`authRepository`).
- `levels.json` and the new `achievement_catalog.json` stay bundled and static always (never fetched from Firestore) — they're reference content, not per-user data. `profile.json`/`topics.json` stay bundled too, but change role to **fallback-only** (used by `ProfileRepository.preview()` and `load(for:)`'s failure path) — matching the established convention that bundled JSON is demoted to a fallback, never deleted (see `QuestionRepository`/`questions.json` in sub-project 4).
- The 4 achievements gated on unbuilt subsystems (interview sessions, leaderboard rank) get `criterion.kind == "unbuildable"` in the catalog — `AchievementEngine` always renders these `.locked` with no progress, regardless of stats. Do not invent fake tracking for them.
- Firestore rules: the existing `users/{uid}` owner-only rule does not automatically cover a subcollection under it — `dailyCompletions` needs its own nested `match` block.

---

## Task 1: Achievement catalog models + bundled catalog content

**Files:**
- Create: `SwiftUp/Models/AchievementDefinition.swift`
- Create: `SwiftUp/Resources/achievement_catalog.json`
- Create: `SwiftUpTests/Fixtures/achievement_catalog.json` (identical copy)
- Modify: `SwiftUpTests/ModelDecodingTests.swift` (add a decode test for the new model)

Note: `SwiftUp/Resources/achievements.json`/`SwiftUpTests/Fixtures/achievements.json` (the old file, superseded by the catalog below) are deleted in **Task 6**, not here — `ProfileRepository.init` still reads `"achievements"` by filename until Task 6 rewrites it, so deleting it now would make `decodeJSONResource` hit its missing-file `assertionFailure` (a Debug-build crash) the next time anything constructs a `ProfileRepository` before Task 6 lands.

**Interfaces:**
- Consumes: `AchievementSealKind` (existing, `SwiftUp/DesignSystem/AchievementSeal.swift`).
- Produces (used by Task 4's `AchievementEngine`, Task 6's `ProfileRepository`):
  - `struct AchievementCriterion: Codable { let kind: String; let topic: String?; let minAccuracy: Int?; let minAnswered: Int?; let count: Int?; let days: Int? }`
  - `struct AchievementDefinition: Codable, Identifiable { let id: String; let title: String; let detail: String; let sealKind: AchievementSealKind; let xpReward: Int; let criterion: AchievementCriterion }`

- [ ] **Step 1: Create the models**

Create `SwiftUp/Models/AchievementDefinition.swift`:

```swift
import Foundation

/// A flat, plain-Codable description of what unlocks an achievement — deliberately not an
/// associated-value enum (this codebase's models stay plain structs/string enums; see
/// `QuestionFormat`). `kind` selects which optional fields apply:
///   - "streak": days
///   - "totalAnswered": count
///   - "perfectDays": count (all-time days with a perfect 5/5)
///   - "topicMastery": topic, minAccuracy, minAnswered
///   - "perfectWeek": (no fields) — 6 of the last 7 calendar days at >=4/5
///   - "perfectMonth": (no fields) — every day so far this calendar month at >=4/5
///   - "onboarded": (no fields) — at least one completed daily quiz
///   - "level": count (target level number)
///   - "unbuildable": (no fields) — depends on a subsystem not built yet; always locked
struct AchievementCriterion: Codable {
    let kind: String
    let topic: String?
    let minAccuracy: Int?
    let minAnswered: Int?
    let count: Int?
    let days: Int?
}

/// Static catalog entry — title/detail/reward/unlock-rule never vary per user.
/// Per-user status/progress is computed at runtime by `AchievementEngine` (Task 4), never stored here.
struct AchievementDefinition: Codable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let sealKind: AchievementSealKind
    let xpReward: Int
    let criterion: AchievementCriterion
}
```

- [ ] **Step 2: Author the bundled catalog (24 entries, same ids/titles/details/sealKinds/rewards as the retiring `achievements.json`, each now with a `criterion`)**

Create `SwiftUp/Resources/achievement_catalog.json`:

```json
[
  {"id": "a01", "title": "Perfect week", "detail": "Six of seven days at 4/5 or better", "sealKind": "perfectWeek", "xpReward": 200, "criterion": {"kind": "perfectWeek", "topic": null, "minAccuracy": null, "minAnswered": null, "count": null, "days": null}},
  {"id": "a02", "title": "Thirty in a row", "detail": "A 30-day streak", "sealKind": "streakMilestone", "xpReward": 150, "criterion": {"kind": "streak", "topic": null, "minAccuracy": null, "minAnswered": null, "count": null, "days": 30}},
  {"id": "a03", "title": "Concurrency, mastered", "detail": "90% across 40 questions in one topic", "sealKind": "topicMastery", "xpReward": 250, "criterion": {"kind": "topicMastery", "topic": "Concurrency", "minAccuracy": 90, "minAnswered": 40, "count": null, "days": null}},
  {"id": "a04", "title": "First interview session", "detail": "Completed a timed prep session end to end", "sealKind": "firstSession", "xpReward": 100, "criterion": {"kind": "unbuildable", "topic": null, "minAccuracy": null, "minAnswered": null, "count": null, "days": null}},
  {"id": "a05", "title": "Seven in a row", "detail": "Your first full week's streak", "sealKind": "streakMilestone", "xpReward": 50, "criterion": {"kind": "streak", "topic": null, "minAccuracy": null, "minAnswered": null, "count": null, "days": 7}},
  {"id": "a06", "title": "Fast learner", "detail": "Ten perfect 5/5 days", "sealKind": "perfectWeek", "xpReward": 100, "criterion": {"kind": "perfectDays", "topic": null, "minAccuracy": null, "minAnswered": null, "count": 10, "days": null}},
  {"id": "a07", "title": "Swift language, mastered", "detail": "90% across 30 questions in one topic", "sealKind": "topicMastery", "xpReward": 200, "criterion": {"kind": "topicMastery", "topic": "Swift language", "minAccuracy": 90, "minAnswered": 30, "count": null, "days": null}},
  {"id": "a08", "title": "Century club", "detail": "100 questions answered", "sealKind": "firstSession", "xpReward": 75, "criterion": {"kind": "totalAnswered", "topic": null, "minAccuracy": null, "minAnswered": null, "count": 100, "days": null}},
  {"id": "a09", "title": "Onboarded", "detail": "Finished onboarding and day one", "sealKind": "firstSession", "xpReward": 25, "criterion": {"kind": "onboarded", "topic": null, "minAccuracy": null, "minAnswered": null, "count": null, "days": null}},
  {"id": "a10", "title": "Fifty in a row", "detail": "A 50-day streak", "sealKind": "streakMilestone", "xpReward": 250, "criterion": {"kind": "streak", "topic": null, "minAccuracy": null, "minAnswered": null, "count": null, "days": 50}},
  {"id": "a11", "title": "Cycle breaker", "detail": "Reach 80% accuracy in Memory · ARC", "sealKind": "topicMastery", "xpReward": 300, "criterion": {"kind": "topicMastery", "topic": "Memory · ARC", "minAccuracy": 80, "minAnswered": 20, "count": null, "days": null}},
  {"id": "a12", "title": "Hundred in a row", "detail": "A 100-day streak", "sealKind": "streakMilestone", "xpReward": 400, "criterion": {"kind": "streak", "topic": null, "minAccuracy": null, "minAnswered": null, "count": null, "days": 100}},
  {"id": "a13", "title": "Architecture, mastered", "detail": "90% across 40 questions in one topic", "sealKind": "topicMastery", "xpReward": 250, "criterion": {"kind": "topicMastery", "topic": "Architecture", "minAccuracy": 90, "minAnswered": 40, "count": null, "days": null}},
  {"id": "a14", "title": "Networking, mastered", "detail": "90% across 30 questions in one topic", "sealKind": "topicMastery", "xpReward": 200, "criterion": {"kind": "topicMastery", "topic": "Networking", "minAccuracy": 90, "minAnswered": 30, "count": null, "days": null}},
  {"id": "a15", "title": "Perfect month", "detail": "Every day this month at 4/5 or better", "sealKind": "perfectWeek", "xpReward": 500, "criterion": {"kind": "perfectMonth", "topic": null, "minAccuracy": null, "minAnswered": null, "count": null, "days": null}},
  {"id": "a16", "title": "Interview ready", "detail": "Reviewed every category in the FAQ bank once", "sealKind": "firstSession", "xpReward": 300, "criterion": {"kind": "unbuildable", "topic": null, "minAccuracy": null, "minAnswered": null, "count": null, "days": null}},
  {"id": "a17", "title": "Five hundred club", "detail": "500 questions answered", "sealKind": "firstSession", "xpReward": 150, "criterion": {"kind": "totalAnswered", "topic": null, "minAccuracy": null, "minAnswered": null, "count": 500, "days": null}},
  {"id": "a18", "title": "Thousand club", "detail": "1,000 questions answered", "sealKind": "firstSession", "xpReward": 300, "criterion": {"kind": "totalAnswered", "topic": null, "minAccuracy": null, "minAnswered": null, "count": 1000, "days": null}},
  {"id": "a19", "title": "SwiftUI, mastered", "detail": "90% across 40 questions in one topic", "sealKind": "topicMastery", "xpReward": 250, "criterion": {"kind": "topicMastery", "topic": "SwiftUI state", "minAccuracy": 90, "minAnswered": 40, "count": null, "days": null}},
  {"id": "a20", "title": "Testing, mastered", "detail": "90% across 25 questions in one topic", "sealKind": "topicMastery", "xpReward": 200, "criterion": {"kind": "topicMastery", "topic": "Testing", "minAccuracy": 90, "minAnswered": 25, "count": null, "days": null}},
  {"id": "a21", "title": "Two hundred in a row", "detail": "A 200-day streak", "sealKind": "streakMilestone", "xpReward": 600, "criterion": {"kind": "streak", "topic": null, "minAccuracy": null, "minAnswered": null, "count": null, "days": 200}},
  {"id": "a22", "title": "Second session", "detail": "Completed two timed prep sessions", "sealKind": "firstSession", "xpReward": 100, "criterion": {"kind": "unbuildable", "topic": null, "minAccuracy": null, "minAnswered": null, "count": null, "days": null}},
  {"id": "a23", "title": "Level ten", "detail": "Reach Systems Designer", "sealKind": "perfectWeek", "xpReward": 400, "criterion": {"kind": "level", "topic": null, "minAccuracy": null, "minAnswered": null, "count": 10, "days": null}},
  {"id": "a24", "title": "Top of the board", "detail": "Finish first on the weekly leaderboard", "sealKind": "streakMilestone", "xpReward": 350, "criterion": {"kind": "unbuildable", "topic": null, "minAccuracy": null, "minAnswered": null, "count": null, "days": null}}
]
```

- [ ] **Step 3: Copy it into the test fixtures directory**

```bash
cp "SwiftUp/Resources/achievement_catalog.json" "SwiftUpTests/Fixtures/achievement_catalog.json"
```

- [ ] **Step 4: Add a decode test**

In `SwiftUpTests/ModelDecodingTests.swift`, add this test to the `ModelDecodingTests` struct (after `decodesAchievementWithSealKind`):

```swift
    @Test func decodesAchievementDefinitionWithCriterion() throws {
        let json = """
        {
          "id": "a03", "title": "Concurrency, mastered", "detail": "90% across 40 questions in one topic",
          "sealKind": "topicMastery", "xpReward": 250,
          "criterion": {"kind": "topicMastery", "topic": "Concurrency", "minAccuracy": 90, "minAnswered": 40, "count": null, "days": null}
        }
        """.data(using: .utf8)!
        let d = try JSONDecoder().decode(AchievementDefinition.self, from: json)
        #expect(d.criterion.kind == "topicMastery")
        #expect(d.criterion.topic == "Concurrency")
        #expect(d.criterion.minAccuracy == 90)
    }
```

- [ ] **Step 5: Verify it builds and the new test passes**

Run:
```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
xcodegen generate
xcodebuild test -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SwiftUpTests/ModelDecodingTests
```
Expected: all `ModelDecodingTests` PASS, including the new one.

- [ ] **Step 6: Commit**

```bash
git add SwiftUp/Models/AchievementDefinition.swift SwiftUp/Resources/achievement_catalog.json SwiftUpTests/Fixtures/achievement_catalog.json SwiftUpTests/ModelDecodingTests.swift
git commit -m "$(cat <<'EOF'
Split achievement catalog into static definitions + unlock criteria

Replaces achievements.json's baked-in per-user status/progress with
a static catalog (title/detail/reward/criterion) — per-user state is
computed at runtime by AchievementEngine (added next), never stored
as flat mock data.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011chT6wfnejdTy5GNuykG51
EOF
)"
```

---

## Task 2: `LevelCalculator` (pure)

**Files:**
- Create: `SwiftUp/Data/LevelCalculator.swift`
- Test: `SwiftUpTests/LevelCalculatorTests.swift`

**Interfaces:**
- Consumes: `LevelInfo` (existing model).
- Produces (used by Task 4, Task 6): `enum LevelCalculator { static func level(for totalXP: Int, ladder: [LevelInfo]) -> (number: Int, title: String, xpForCurrentLevel: Int, xpForNextLevel: Int) }`

- [ ] **Step 1: Write the failing tests**

Create `SwiftUpTests/LevelCalculatorTests.swift`:

```swift
import Testing
@testable import SwiftUp

private let testLadder = [
    LevelInfo(number: 1, title: "Swift Novice", xpThreshold: 0),
    LevelInfo(number: 2, title: "Optional Handler", xpThreshold: 150),
    LevelInfo(number: 3, title: "Protocol Wrangler", xpThreshold: 400),
]

struct LevelCalculatorTests {
    @Test func zeroXPIsLevelOne() {
        let result = LevelCalculator.level(for: 0, ladder: testLadder)
        #expect(result.number == 1)
        #expect(result.title == "Swift Novice")
        #expect(result.xpForCurrentLevel == 0)
        #expect(result.xpForNextLevel == 150)
    }

    @Test func midLevelBand() {
        let result = LevelCalculator.level(for: 200, ladder: testLadder)
        #expect(result.number == 2)
        #expect(result.title == "Optional Handler")
        #expect(result.xpForCurrentLevel == 150)
        #expect(result.xpForNextLevel == 400)
    }

    @Test func exactlyAtThreshold() {
        let result = LevelCalculator.level(for: 400, ladder: testLadder)
        #expect(result.number == 3)
    }

    @Test func aboveCeilingStaysAtTopLevel() {
        let result = LevelCalculator.level(for: 999_999, ladder: testLadder)
        #expect(result.number == 3)
        #expect(result.title == "Protocol Wrangler")
        #expect(result.xpForCurrentLevel == 400)
        #expect(result.xpForNextLevel == 400) // no level above 3 — matches "xp to next level" clamping at 0
    }

    @Test func emptyLadderFallsBackToLevelOne() {
        let result = LevelCalculator.level(for: 500, ladder: [])
        #expect(result.number == 1)
        #expect(result.xpForCurrentLevel == 0)
        #expect(result.xpForNextLevel == 0)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
xcodegen generate
xcodebuild test -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SwiftUpTests/LevelCalculatorTests
```
Expected: FAIL — `LevelCalculator` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `SwiftUp/Data/LevelCalculator.swift`:

```swift
import Foundation

enum LevelCalculator {
    /// Finds the highest level whose threshold the given XP total has reached.
    /// `xpForNextLevel` equals `xpForCurrentLevel` at the ladder's ceiling (level 12), so
    /// `UserProfile.xpToNextLevel`'s `max(0, ...)` clamp reads that as "maxed out," not negative.
    static func level(for totalXP: Int, ladder: [LevelInfo]) -> (number: Int, title: String, xpForCurrentLevel: Int, xpForNextLevel: Int) {
        let sorted = ladder.sorted { $0.number < $1.number }
        guard let first = sorted.first else {
            return (number: 1, title: "", xpForCurrentLevel: 0, xpForNextLevel: 0)
        }
        var current = first
        for level in sorted where level.xpThreshold <= totalXP {
            current = level
        }
        let next = sorted.first { $0.number == current.number + 1 }
        return (
            number: current.number,
            title: current.title,
            xpForCurrentLevel: current.xpThreshold,
            xpForNextLevel: next?.xpThreshold ?? current.xpThreshold
        )
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Same command as Step 2. Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/Data/LevelCalculator.swift SwiftUpTests/LevelCalculatorTests.swift
git commit -m "$(cat <<'EOF'
Add LevelCalculator: pure XP-to-level lookup against the level ladder

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011chT6wfnejdTy5GNuykG51
EOF
)"
```

---

## Task 3: `StreakCalculator` (pure)

**Files:**
- Create: `SwiftUp/Data/StreakCalculator.swift`
- Test: `SwiftUpTests/StreakCalculatorTests.swift`

**Interfaces:**
- Produces (used by Task 6): `enum StreakCalculator { static func apply(lastCompletedDate: String?, streakDays: Int, freezesAvailable: Int, today: String) -> (streakDays: Int, freezesAvailable: Int) }` — dates are `"yyyy-MM-dd"` strings.

- [ ] **Step 1: Write the failing tests**

Create `SwiftUpTests/StreakCalculatorTests.swift`:

```swift
import Testing
@testable import SwiftUp

struct StreakCalculatorTests {
    @Test func firstEverCompletionStartsStreakAtOne() {
        let result = StreakCalculator.apply(lastCompletedDate: nil, streakDays: 0, freezesAvailable: 0, today: "2026-01-10")
        #expect(result.streakDays == 1)
        #expect(result.freezesAvailable == 0)
    }

    @Test func sameDayIsIdempotent() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 1, today: "2026-01-10")
        #expect(result.streakDays == 5)
        #expect(result.freezesAvailable == 1)
    }

    @Test func consecutiveDayGrowsStreak() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 0, today: "2026-01-11")
        #expect(result.streakDays == 6)
        #expect(result.freezesAvailable == 0)
    }

    @Test func crossingSevenGrantsAFreeze() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 6, freezesAvailable: 0, today: "2026-01-11")
        #expect(result.streakDays == 7)
        #expect(result.freezesAvailable == 1)
    }

    @Test func freezesCapAtThree() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 20, freezesAvailable: 3, today: "2026-01-11")
        #expect(result.streakDays == 21)
        #expect(result.freezesAvailable == 3)
    }

    @Test func oneDayGapWithFreezeAvailableConsumesItAndContinuesStreak() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 1, today: "2026-01-12")
        #expect(result.streakDays == 6)
        #expect(result.freezesAvailable == 0)
    }

    @Test func oneDayGapWithNoFreezeResetsStreak() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 0, today: "2026-01-12")
        #expect(result.streakDays == 1)
        #expect(result.freezesAvailable == 0)
    }

    @Test func widerGapResetsStreakEvenWithAFreezeAvailable() {
        // A freeze forgives exactly one missed day — a 2-day gap is too wide for one freeze to cover.
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 1, today: "2026-01-14")
        #expect(result.streakDays == 1)
        #expect(result.freezesAvailable == 1) // not consumed
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
xcodegen generate
xcodebuild test -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SwiftUpTests/StreakCalculatorTests
```
Expected: FAIL — `StreakCalculator` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `SwiftUp/Data/StreakCalculator.swift`:

```swift
import Foundation

enum StreakCalculator {
    /// `lastCompletedDate`/`today` are `"yyyy-MM-dd"` local-calendar-day strings (same format as
    /// `QuestionSelector.todaySeed`'s date component). A freeze forgives exactly one missed day;
    /// every 7th consecutive streak day grants one back, capped at 3 banked.
    static func apply(
        lastCompletedDate: String?, streakDays: Int, freezesAvailable: Int, today: String
    ) -> (streakDays: Int, freezesAvailable: Int) {
        guard let lastCompletedDate, let gap = daysBetween(lastCompletedDate, today), gap > 0 else {
            // No prior completion: today starts streak day 1. Same-day or unparseable/negative gap: no-op.
            return lastCompletedDate == nil ? (1, freezesAvailable) : (streakDays, freezesAvailable)
        }
        switch gap {
        case 1:
            return grow(streakDays: streakDays, freezesAvailable: freezesAvailable)
        case 2 where freezesAvailable > 0:
            return grow(streakDays: streakDays, freezesAvailable: freezesAvailable - 1)
        default:
            return (1, freezesAvailable)
        }
    }

    private static func grow(streakDays: Int, freezesAvailable: Int) -> (Int, Int) {
        let newStreak = streakDays + 1
        let freezes = newStreak % 7 == 0 ? min(freezesAvailable + 1, 3) : freezesAvailable
        return (newStreak, freezes)
    }

    private static func daysBetween(_ start: String, _ end: String) -> Int? {
        guard let startDate = dateFormatter.date(from: start), let endDate = dateFormatter.date(from: end) else {
            return nil
        }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: startDate, to: endDate).day
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
```

- [ ] **Step 4: Run to verify it passes**

Same command as Step 2. Expected: all 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/Data/StreakCalculator.swift SwiftUpTests/StreakCalculatorTests.swift
git commit -m "$(cat <<'EOF'
Add StreakCalculator: pure streak/freeze rollover logic

One freeze forgives exactly one missed day; every 7th consecutive
streak day banks a freeze, capped at 3.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011chT6wfnejdTy5GNuykG51
EOF
)"
```

---

## Task 4: `AchievementEngine` + `UserStats` (pure)

**Files:**
- Create: `SwiftUp/Data/AchievementEngine.swift`
- Test: `SwiftUpTests/AchievementEngineTests.swift`

**Interfaces:**
- Consumes: `AchievementDefinition`, `AchievementCriterion` (Task 1); `Achievement`, `AchievementStatus` (existing).
- Produces (used by Task 6's `ProfileRepository`):
  - `struct UserStats { let totalXP: Int; let currentLevel: Int; let streakDays: Int; let totalQuestionsAnswered: Int; let perfectDayCount: Int; let topicStats: [String: (correct: Int, total: Int)]; let recentCompletions: [(date: String, correctCount: Int)]; let today: String }`
  - `enum AchievementEngine { static func evaluate(catalog: [AchievementDefinition], stats: UserStats, earnedAt: [String: Date]) -> [Achievement] }`

- [ ] **Step 1: Write the failing tests**

Create `SwiftUpTests/AchievementEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftUp

private func definition(_ id: String, kind: String, topic: String? = nil, minAccuracy: Int? = nil, minAnswered: Int? = nil, count: Int? = nil, days: Int? = nil) -> AchievementDefinition {
    AchievementDefinition(
        id: id, title: "Title \(id)", detail: "Detail", sealKind: .firstSession, xpReward: 50,
        criterion: AchievementCriterion(kind: kind, topic: topic, minAccuracy: minAccuracy, minAnswered: minAnswered, count: count, days: days)
    )
}

private func emptyStats(today: String = "2026-01-15") -> UserStats {
    UserStats(totalXP: 0, currentLevel: 1, streakDays: 0, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: [], today: today)
}

struct AchievementEngineTests {
    @Test func streakEarnedWhenThresholdMet() {
        let stats = UserStats(totalXP: 0, currentLevel: 1, streakDays: 7, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "streak", days: 7)], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func streakInReachBelowThreshold() {
        let stats = UserStats(totalXP: 0, currentLevel: 1, streakDays: 3, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "streak", days: 7)], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .inReach)
        #expect(result.first?.progressCurrent == 3)
        #expect(result.first?.progressTarget == 7)
    }

    @Test func lockedWithNoProgress() {
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "streak", days: 7)], stats: emptyStats(), earnedAt: [:])
        #expect(result.first?.status == .locked)
    }

    @Test func totalAnsweredEarned() {
        let stats = UserStats(totalXP: 0, currentLevel: 1, streakDays: 0, totalQuestionsAnswered: 100, perfectDayCount: 0, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "totalAnswered", count: 100)], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func perfectDaysEarned() {
        let stats = UserStats(totalXP: 0, currentLevel: 1, streakDays: 0, totalQuestionsAnswered: 0, perfectDayCount: 10, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "perfectDays", count: 10)], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func topicMasteryEarnedWhenAccuracyAndCountMet() {
        let stats = UserStats(totalXP: 0, currentLevel: 1, streakDays: 0, totalQuestionsAnswered: 40, perfectDayCount: 0, topicStats: ["Concurrency": (correct: 36, total: 40)], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "topicMastery", topic: "Concurrency", minAccuracy: 90, minAnswered: 40)], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func topicMasteryNotEarnedWhenCountTooLow() {
        // 100% accuracy but only 5 answered, needs 40.
        let stats = UserStats(totalXP: 0, currentLevel: 1, streakDays: 0, totalQuestionsAnswered: 5, perfectDayCount: 0, topicStats: ["Concurrency": (correct: 5, total: 5)], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "topicMastery", topic: "Concurrency", minAccuracy: 90, minAnswered: 40)], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .inReach)
        #expect(result.first?.progressCurrent == 100)
    }

    @Test func perfectWeekEarnedWithSixOfSevenGoodDays() {
        let recent: [(date: String, correctCount: Int)] = [
            ("2026-01-09", 5), ("2026-01-10", 4), ("2026-01-11", 5), ("2026-01-12", 2),
            ("2026-01-13", 4), ("2026-01-14", 5), ("2026-01-15", 5),
        ]
        let stats = UserStats(totalXP: 0, currentLevel: 1, streakDays: 0, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: recent, today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "perfectWeek")], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func perfectWeekNotEarnedWithOnlyFiveGoodDays() {
        // Only 5 of the last 7 calendar days have a good (>=4/5) completion — 2026-01-10 and
        // 2026-01-15 (today) both have no entry at all — below the "6 of 7" threshold.
        let recent: [(date: String, correctCount: Int)] = [
            ("2026-01-09", 5), ("2026-01-11", 5), ("2026-01-12", 5),
            ("2026-01-13", 5), ("2026-01-14", 5),
        ]
        let stats = UserStats(totalXP: 0, currentLevel: 1, streakDays: 0, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: recent, today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "perfectWeek")], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .locked)
    }

    @Test func perfectMonthEarnedForEveryDaySoFar() {
        let recent: [(date: String, correctCount: Int)] = [
            ("2026-01-01", 5), ("2026-01-02", 4), ("2026-01-03", 5),
        ]
        let stats = UserStats(totalXP: 0, currentLevel: 1, streakDays: 0, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: recent, today: "2026-01-03")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "perfectMonth")], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func onboardedEarnedAfterFirstAnswer() {
        let stats = UserStats(totalXP: 0, currentLevel: 1, streakDays: 0, totalQuestionsAnswered: 5, perfectDayCount: 0, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "onboarded")], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func levelEarnedWhenReached() {
        let stats = UserStats(totalXP: 7000, currentLevel: 10, streakDays: 0, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "level", count: 10)], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .earned)
    }

    @Test func unbuildableAlwaysLockedRegardlessOfStats() {
        let stats = UserStats(totalXP: 999_999, currentLevel: 12, streakDays: 999, totalQuestionsAnswered: 999_999, perfectDayCount: 999, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "unbuildable")], stats: stats, earnedAt: [:])
        #expect(result.first?.status == .locked)
        #expect(result.first?.progressCurrent == nil)
    }

    @Test func earnedDateDisplayComesFromEarnedAtMap() {
        let stats = UserStats(totalXP: 0, currentLevel: 1, streakDays: 7, totalQuestionsAnswered: 0, perfectDayCount: 0, topicStats: [:], recentCompletions: [], today: "2026-01-15")
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 7
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let result = AchievementEngine.evaluate(catalog: [definition("a1", kind: "streak", days: 7)], stats: stats, earnedAt: ["a1": date])
        #expect(result.first?.status == .earned)
        #expect(result.first?.earnedDateDisplay == "7 Sep")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
xcodegen generate
xcodebuild test -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SwiftUpTests/AchievementEngineTests
```
Expected: FAIL — `AchievementEngine`/`UserStats` don't exist yet.

- [ ] **Step 3: Implement**

Create `SwiftUp/Data/AchievementEngine.swift`:

```swift
import Foundation

/// Everything AchievementEngine needs to evaluate every criterion kind. Built by ProfileRepository
/// from stored Firestore fields (or bundled fallback data) — never persisted in this shape itself.
struct UserStats {
    let totalXP: Int
    let currentLevel: Int
    let streakDays: Int
    let totalQuestionsAnswered: Int
    let perfectDayCount: Int
    let topicStats: [String: (correct: Int, total: Int)]
    let recentCompletions: [(date: String, correctCount: Int)]   // any order; last ~31 calendar days
    let today: String   // "yyyy-MM-dd"
}

enum AchievementEngine {
    /// `earnedAt` are timestamps for achievements already recorded as earned (from
    /// `users/{uid}.earnedAchievementIDs`) — used only for `earnedDateDisplay`, not for deciding
    /// whether something is newly earned (the caller compares this function's output against
    /// `earnedAt`'s keys to find that).
    static func evaluate(catalog: [AchievementDefinition], stats: UserStats, earnedAt: [String: Date]) -> [Achievement] {
        catalog.map { definition in
            let (isEarned, progress) = evaluateCriterion(definition.criterion, stats: stats)
            let status: AchievementStatus = isEarned ? .earned : ((progress?.current ?? 0) > 0 ? .inReach : .locked)
            return Achievement(
                id: definition.id,
                title: definition.title,
                detail: definition.detail,
                sealKind: definition.sealKind,
                status: status,
                xpReward: definition.xpReward,
                earnedDateDisplay: earnedAt[definition.id].map { displayFormatter.string(from: $0) },
                progressCurrent: status == .earned ? nil : progress?.current,
                progressTarget: status == .earned ? nil : progress?.target
            )
        }
    }

    private static func evaluateCriterion(
        _ criterion: AchievementCriterion, stats: UserStats
    ) -> (earned: Bool, progress: (current: Int, target: Int)?) {
        switch criterion.kind {
        case "streak":
            let target = criterion.days ?? 0
            return (stats.streakDays >= target, (stats.streakDays, target))

        case "totalAnswered":
            let target = criterion.count ?? 0
            return (stats.totalQuestionsAnswered >= target, (stats.totalQuestionsAnswered, target))

        case "perfectDays":
            let target = criterion.count ?? 0
            return (stats.perfectDayCount >= target, (stats.perfectDayCount, target))

        case "topicMastery":
            guard let topic = criterion.topic, let stat = stats.topicStats[topic], stat.total > 0 else {
                return (false, nil)
            }
            let accuracy = Int((Double(stat.correct) / Double(stat.total) * 100).rounded())
            let minAccuracy = criterion.minAccuracy ?? 0
            let minAnswered = criterion.minAnswered ?? 0
            return (accuracy >= minAccuracy && stat.total >= minAnswered, (accuracy, minAccuracy))

        case "perfectWeek":
            let dates = lastNDates(before: stats.today, count: 7)
            let goodDays = dates.filter { isGoodDay($0, in: stats.recentCompletions) }.count
            return (goodDays >= 6, nil)

        case "perfectMonth":
            let dates = datesSoFarThisMonth(today: stats.today)
            let goodDays = dates.filter { isGoodDay($0, in: stats.recentCompletions) }.count
            return (!dates.isEmpty && goodDays == dates.count, nil)

        case "onboarded":
            return (stats.totalQuestionsAnswered > 0, nil)

        case "level":
            let target = criterion.count ?? 0
            return (stats.currentLevel >= target, (stats.currentLevel, target))

        default: // "unbuildable" and any unrecognized kind
            return (false, nil)
        }
    }

    private static func isGoodDay(_ date: String, in completions: [(date: String, correctCount: Int)]) -> Bool {
        completions.first { $0.date == date }.map { $0.correctCount >= 4 } ?? false
    }

    private static func lastNDates(before today: String, count: Int) -> [String] {
        guard let todayDate = dateFormatter.date(from: today) else { return [] }
        let calendar = Calendar(identifier: .gregorian)
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: todayDate).map(dateFormatter.string(from:))
        }
    }

    private static func datesSoFarThisMonth(today: String) -> [String] {
        guard let todayDate = dateFormatter.date(from: today) else { return [] }
        let calendar = Calendar(identifier: .gregorian)
        guard
            let range = calendar.range(of: .day, in: .month, for: todayDate),
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: todayDate))
        else { return [] }
        return range.compactMap { day in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart), date <= todayDate else {
                return nil
            }
            return dateFormatter.string(from: date)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        return formatter
    }()
}
```

- [ ] **Step 4: Run to verify it passes**

Same command as Step 2. Expected: all 14 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/Data/AchievementEngine.swift SwiftUpTests/AchievementEngineTests.swift
git commit -m "$(cat <<'EOF'
Add AchievementEngine: pure per-user achievement status/progress

Evaluates the static catalog's criteria against live UserStats —
status/progress are computed here, never stored as flat mock data.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011chT6wfnejdTy5GNuykG51
EOF
)"
```

---

## Task 5: Firestore rules for `dailyCompletions`

**Files:**
- Modify: `firestore.rules`

**Interfaces:** None (infrastructure only).

- [ ] **Step 1: Add the nested subcollection rule**

In `firestore.rules`, replace:

```
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
```

with:

```
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
      match /dailyCompletions/{date} {
        allow read, write: if request.auth != null && request.auth.uid == uid;
      }
    }
```

The full file becomes:

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
  }
}
```

- [ ] **Step 2: Deploy the updated rules**

The Firebase CLI is already installed and authenticated against this project (`swiftup-9eee9`, linked via `.firebaserc`/`firebase.json`) from setting up sub-project 4's live deploy.

Run:
```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
firebase deploy --only firestore:rules
```
Expected: `✔ Deploy complete!` — a `cloud.firestore: rules file firestore.rules compiled successfully` line confirms the new nested rule parsed correctly.

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "$(cat <<'EOF'
Add Firestore rule for users/{uid}/dailyCompletions subcollection

A subcollection under users/{uid} needs its own nested match block —
the parent's owner-only rule doesn't automatically cover it.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011chT6wfnejdTy5GNuykG51
EOF
)"
```

---

## Task 6: `ProfileRepository` rewrite (Firestore-backed, async, with fallback)

**Files:**
- Modify: `SwiftUp/Data/ProfileRepository.swift` (full rewrite)
- Modify: `SwiftUpTests/RepositoryTests.swift:14-19` (update the one test that constructs `ProfileRepository` directly)
- Delete: `SwiftUp/Resources/achievements.json`, `SwiftUpTests/Fixtures/achievements.json` (superseded by Task 1's `achievement_catalog.json` — deleted here, not in Task 1, because this is the step where `ProfileRepository` actually stops reading the `"achievements"` filename)

**Interfaces:**
- Consumes: `LevelInfo`, `AchievementDefinition`, `UserProfile`, `TopicAccuracy`, `Achievement` (existing/Task 1); `LevelCalculator` (Task 2); `StreakCalculator` (Task 3); `AchievementEngine`, `UserStats` (Task 4); `QuizSession` (existing — `questions`, `correctCount`, `totalXPEarned`, `selectedOptionID(for:)`).
- Produces (used by Task 7):
  - `@Observable final class ProfileRepository`
  - `init(bundle: Bundle = .main)` — no Firebase touch; loads only static `levels`/catalog synchronously
  - `static func preview(bundle: Bundle = .main) -> ProfileRepository` — synchronous bundled fallback, safe for `#Preview`, never touches Firestore
  - `let levels: [LevelInfo]`
  - `private(set) var profile: UserProfile`
  - `private(set) var topics: [TopicAccuracy]`
  - `private(set) var achievements: [Achievement]`
  - `private(set) var isLoading: Bool`
  - `var earnedAchievements: [Achievement]`, `var inReachAchievements: [Achievement]`, `var lockedAchievements: [Achievement]` (unchanged filters, kept for existing view call sites)
  - `func load(for uid: String) async`
  - `func recordCompletion(_ session: QuizSession, for uid: String) async`

- [ ] **Step 1: Rewrite `ProfileRepository.swift`**

Replace `SwiftUp/Data/ProfileRepository.swift` entirely:

```swift
import Foundation
import FirebaseFirestore

@Observable
final class ProfileRepository {
    let levels: [LevelInfo]
    private let catalog: [AchievementDefinition]

    private(set) var profile: UserProfile
    private(set) var topics: [TopicAccuracy] = []
    private(set) var achievements: [Achievement] = []
    private(set) var isLoading = false

    init(bundle: Bundle = .main) {
        levels = decodeJSONResource([LevelInfo].self, filename: "levels", bundle: bundle) ?? []
        catalog = decodeJSONResource([AchievementDefinition].self, filename: "achievement_catalog", bundle: bundle) ?? []
        let level = LevelCalculator.level(for: 0, ladder: levels)
        profile = UserProfile(
            name: "", initials: "", level: level.number, levelTitle: level.title,
            xp: 0, xpForCurrentLevel: level.xpForCurrentLevel, xpForNextLevel: level.xpForNextLevel,
            streakDays: 0, freezesAvailable: 0, freezesTotal: 3,
            answeredCount: 0, accuracyPercent: 0, memberSinceDisplay: ""
        )
    }

    /// Synchronously loads bundled fallback content — safe for #Preview, never touches Firestore.
    static func preview(bundle: Bundle = .main) -> ProfileRepository {
        let repo = ProfileRepository(bundle: bundle)
        repo.applyBundledFallback(bundle: bundle)
        return repo
    }

    private func applyBundledFallback(bundle: Bundle) {
        let fallbackProfile = decodeJSONResource(UserProfile.self, filename: "profile", bundle: bundle) ?? profile
        let fallbackTopics = decodeJSONResource([TopicAccuracy].self, filename: "topics", bundle: bundle) ?? []
        let level = LevelCalculator.level(for: fallbackProfile.xp, ladder: levels)
        let stats = UserStats(
            totalXP: fallbackProfile.xp, currentLevel: level.number, streakDays: fallbackProfile.streakDays,
            totalQuestionsAnswered: fallbackProfile.answeredCount, perfectDayCount: 0,
            topicStats: [:], recentCompletions: [], today: Self.todayString()
        )
        profile = fallbackProfile
        topics = fallbackTopics
        achievements = AchievementEngine.evaluate(catalog: catalog, stats: stats, earnedAt: [:])
    }

    /// Fetches this user's real profile/XP/streak/topic/achievement state from Firestore.
    /// Falls back to bundled content only if Firestore is unreachable (e.g. first launch, offline).
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        let userRef = Firestore.firestore().collection("users").document(uid)
        do {
            let snapshot = try await userRef.getDocument()
            let recentCompletions = try await Self.fetchRecentCompletions(uid: uid)
            apply(snapshot: snapshot, recentCompletions: recentCompletions)
        } catch {
            applyBundledFallback(bundle: .main)
        }
    }

    /// Records a finished quiz session: computes updated XP/streak/topic-stats/achievements,
    /// writes them to Firestore in one batch, then reflects the result locally immediately
    /// (no re-fetch round trip). Non-blocking on failure — the user is never blocked leaving the
    /// quiz screen; worst case this session's stats are lost and the next completion recomputes
    /// from whatever's actually stored.
    func recordCompletion(_ session: QuizSession, for uid: String) async {
        guard !session.questions.isEmpty else { return }
        let userRef = Firestore.firestore().collection("users").document(uid)

        do {
            let snapshot = try await userRef.getDocument()
            let existingRecent = try await Self.fetchRecentCompletions(uid: uid)
            let today = Self.todayString()

            var topicStats = Self.decodeTopicStats(snapshot)
            for question in session.questions {
                let wasCorrect = session.selectedOptionID(for: question) == question.correctOptionID
                var entry = topicStats[question.topic] ?? (correct: 0, total: 0)
                entry.total += 1
                if wasCorrect { entry.correct += 1 }
                topicStats[question.topic] = entry
            }

            let previousStreak = (snapshot.get("streakDays") as? Int) ?? 0
            let previousFreezes = (snapshot.get("freezesAvailable") as? Int) ?? 0
            let previousLastCompleted = snapshot.get("lastCompletedDate") as? String
            let streakResult = StreakCalculator.apply(
                lastCompletedDate: previousLastCompleted, streakDays: previousStreak,
                freezesAvailable: previousFreezes, today: today
            )

            let newTotalXP = ((snapshot.get("totalXP") as? Int) ?? 0) + session.totalXPEarned
            let newTotalAnswered = ((snapshot.get("totalQuestionsAnswered") as? Int) ?? 0) + session.questions.count
            let isPerfectDay = session.correctCount == session.questions.count
            let newPerfectDayCount = ((snapshot.get("perfectDayCount") as? Int) ?? 0) + (isPerfectDay ? 1 : 0)
            let level = LevelCalculator.level(for: newTotalXP, ladder: levels)

            var recentCompletions = existingRecent.filter { $0.date != today }
            recentCompletions.append((date: today, correctCount: session.correctCount))

            let stats = UserStats(
                totalXP: newTotalXP, currentLevel: level.number, streakDays: streakResult.streakDays,
                totalQuestionsAnswered: newTotalAnswered, perfectDayCount: newPerfectDayCount,
                topicStats: topicStats, recentCompletions: recentCompletions, today: today
            )

            var earnedAt = Self.decodeEarnedAt(snapshot)
            let evaluatedBeforeNewEarns = AchievementEngine.evaluate(catalog: catalog, stats: stats, earnedAt: earnedAt)
            let newlyEarned = evaluatedBeforeNewEarns.filter { $0.status == .earned && earnedAt[$0.id] == nil }
            let now = Date()
            for achievement in newlyEarned { earnedAt[achievement.id] = now }

            var userUpdates: [String: Any] = [
                "totalXP": newTotalXP,
                "totalQuestionsAnswered": newTotalAnswered,
                "perfectDayCount": newPerfectDayCount,
                "streakDays": streakResult.streakDays,
                "freezesAvailable": streakResult.freezesAvailable,
                "lastCompletedDate": today,
            ]
            for (topic, value) in topicStats {
                userUpdates["topicStats.\(topic).correct"] = value.correct
                userUpdates["topicStats.\(topic).total"] = value.total
            }
            let nowTimestamp = Timestamp(date: now)
            for achievement in newlyEarned {
                userUpdates["earnedAchievementIDs.\(achievement.id)"] = nowTimestamp
            }

            let batch = Firestore.firestore().batch()
            batch.updateData(userUpdates, forDocument: userRef)
            let dayRef = userRef.collection("dailyCompletions").document(today)
            batch.setData(["correctCount": session.correctCount, "xpEarned": session.totalXPEarned], forDocument: dayRef)
            try await batch.commit()

            let freezesAvailable = streakResult.freezesAvailable
            profile = Self.buildProfile(
                displayName: snapshot.get("displayName") as? String,
                createdAt: snapshot.get("createdAt") as? Timestamp,
                freezesAvailable: freezesAvailable, stats: stats, level: level
            )
            topics = topicStats.map { TopicAccuracy(name: $0.key, accuracyPercent: Self.accuracy($0.value)) }.sorted { $0.name < $1.name }
            achievements = AchievementEngine.evaluate(catalog: catalog, stats: stats, earnedAt: earnedAt)
        } catch {
            // Non-blocking — see doc comment above.
        }
    }

    // MARK: - Firestore decode helpers

    private func apply(snapshot: DocumentSnapshot, recentCompletions: [(date: String, correctCount: Int)]) {
        let totalXP = (snapshot.get("totalXP") as? Int) ?? 0
        let totalQuestionsAnswered = (snapshot.get("totalQuestionsAnswered") as? Int) ?? 0
        let perfectDayCount = (snapshot.get("perfectDayCount") as? Int) ?? 0
        let streakDays = (snapshot.get("streakDays") as? Int) ?? 0
        let freezesAvailable = (snapshot.get("freezesAvailable") as? Int) ?? 0
        let topicStats = Self.decodeTopicStats(snapshot)
        let earnedAt = Self.decodeEarnedAt(snapshot)
        let level = LevelCalculator.level(for: totalXP, ladder: levels)

        let stats = UserStats(
            totalXP: totalXP, currentLevel: level.number, streakDays: streakDays,
            totalQuestionsAnswered: totalQuestionsAnswered, perfectDayCount: perfectDayCount,
            topicStats: topicStats, recentCompletions: recentCompletions, today: Self.todayString()
        )

        profile = Self.buildProfile(
            displayName: snapshot.get("displayName") as? String,
            createdAt: snapshot.get("createdAt") as? Timestamp,
            freezesAvailable: freezesAvailable, stats: stats, level: level
        )
        topics = topicStats.map { TopicAccuracy(name: $0.key, accuracyPercent: Self.accuracy($0.value)) }.sorted { $0.name < $1.name }
        achievements = AchievementEngine.evaluate(catalog: catalog, stats: stats, earnedAt: earnedAt)
    }

    private static func buildProfile(
        displayName: String?, createdAt: Timestamp?, freezesAvailable: Int, stats: UserStats,
        level: (number: Int, title: String, xpForCurrentLevel: Int, xpForNextLevel: Int)
    ) -> UserProfile {
        let name = (displayName?.isEmpty == false) ? displayName! : "SwiftUp user"
        UserProfile(
            name: name, initials: initials(from: name), level: level.number, levelTitle: level.title,
            xp: stats.totalXP, xpForCurrentLevel: level.xpForCurrentLevel, xpForNextLevel: level.xpForNextLevel,
            streakDays: stats.streakDays, freezesAvailable: freezesAvailable, freezesTotal: 3,
            answeredCount: stats.totalQuestionsAnswered, accuracyPercent: overallAccuracy(stats.topicStats),
            memberSinceDisplay: memberSinceDisplay(createdAt)
        )
    }

    private static func initials(from name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    private static func overallAccuracy(_ topicStats: [String: (correct: Int, total: Int)]) -> Int {
        let totalCorrect = topicStats.values.reduce(0) { $0 + $1.correct }
        let totalAnswered = topicStats.values.reduce(0) { $0 + $1.total }
        guard totalAnswered > 0 else { return 0 }
        return Int((Double(totalCorrect) / Double(totalAnswered) * 100).rounded())
    }

    private static func accuracy(_ stat: (correct: Int, total: Int)) -> Int {
        guard stat.total > 0 else { return 0 }
        return Int((Double(stat.correct) / Double(stat.total) * 100).rounded())
    }

    private static func memberSinceDisplay(_ timestamp: Timestamp?) -> String {
        guard let timestamp else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        return "Since \(formatter.string(from: timestamp.dateValue()))"
    }

    private static func decodeTopicStats(_ snapshot: DocumentSnapshot) -> [String: (correct: Int, total: Int)] {
        guard let raw = snapshot.get("topicStats") as? [String: [String: Int]] else { return [:] }
        return raw.mapValues { (correct: $0["correct"] ?? 0, total: $0["total"] ?? 0) }
    }

    private static func decodeEarnedAt(_ snapshot: DocumentSnapshot) -> [String: Date] {
        guard let raw = snapshot.get("earnedAchievementIDs") as? [String: Timestamp] else { return [:] }
        return raw.mapValues { $0.dateValue() }
    }

    private static func fetchRecentCompletions(uid: String) async throws -> [(date: String, correctCount: Int)] {
        let snapshot = try await Firestore.firestore()
            .collection("users").document(uid).collection("dailyCompletions")
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: 31)
            .getDocuments()
        return snapshot.documents.compactMap { doc in
            guard let correctCount = doc.get("correctCount") as? Int else { return nil }
            return (date: doc.documentID, correctCount: correctCount)
        }
    }

    private static func todayString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    var earnedAchievements: [Achievement] { achievements.filter { $0.status == .earned } }
    var inReachAchievements: [Achievement] { achievements.filter { $0.status == .inReach } }
    var lockedAchievements: [Achievement] { achievements.filter { $0.status == .locked } }
}
```

- [ ] **Step 2: Update the existing repository test**

In `SwiftUpTests/RepositoryTests.swift`, replace:

```swift
    @Test func profileRepositoryLoadsProfileAndLevels() {
        let repo = ProfileRepository(bundle: testBundle)
        #expect(repo.profile.name == "Maya Reyes")
        #expect(repo.levels.count == 12)
        #expect(repo.achievements.count == 24)
        #expect(repo.topics.count == 12)
    }
```

with:

```swift
    @Test func profileRepositoryLoadsBundledFallback() {
        let repo = ProfileRepository.preview(bundle: testBundle)
        #expect(repo.profile.name == "Maya Reyes")
        #expect(repo.levels.count == 12)
        #expect(repo.achievements.count == 24)
        #expect(repo.topics.count == 12)
    }
```

- [ ] **Step 3: Delete the retiring `achievements.json` from both locations**

Now safe — `ProfileRepository` (rewritten in Step 1) no longer reads the `"achievements"` filename.

```bash
git rm SwiftUp/Resources/achievements.json SwiftUpTests/Fixtures/achievements.json
```

- [ ] **Step 4: Run the full test suite**

```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
xcodegen generate
xcodebuild test -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: `** TEST SUCCEEDED **`. The build succeeds even though several `#Preview` blocks still call bare `ProfileRepository()` — `init(bundle: Bundle = .main)` keeps that call site compiling via its default parameter. Those previews just render an empty/zero profile instead of populated mock data until Task 7 switches them to `.preview()`; that's a preview-only cosmetic gap, not a test failure.

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/Data/ProfileRepository.swift SwiftUpTests/RepositoryTests.swift SwiftUp/Resources/achievements.json SwiftUpTests/Fixtures/achievements.json
git commit -m "$(cat <<'EOF'
Rewrite ProfileRepository as async Firestore-backed with fallback

profile/topics/achievements now come from load(for:) — a Firestore
fetch plus LevelCalculator/StreakCalculator/AchievementEngine — with
recordCompletion(_:for:) as the write path from a finished quiz
session. Falls back to bundled JSON only if Firestore is unreachable.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011chT6wfnejdTy5GNuykG51
EOF
)"
```

---

## Task 7: Wire into the app — load on launch, record on completion, fix previews

**Files:**
- Modify: `SwiftUp/App/RootView.swift`
- Modify: `SwiftUp/Features/DailyQuiz/TodayFlowView.swift`
- Modify: `SwiftUp/Features/Profile/ProfileHomeView.swift`
- Modify: `SwiftUp/App/MainTabView.swift`, `SwiftUp/Features/DailyQuiz/DailyQuizEntryView.swift`, `SwiftUp/Features/Profile/AccuracyByTopicView.swift`, `SwiftUp/Features/Profile/BadgesView.swift`, `SwiftUp/Features/Profile/MilestonesView.swift`, `SwiftUp/Features/Profile/AllLevelsView.swift` (each: `#Preview` only)

**Interfaces:**
- Consumes: `ProfileRepository.load(for:)`, `.recordCompletion(_:for:)`, `.isLoading`, `.preview()` (Task 6); `QuestionRepository.load(for:)` (existing, sub-project 4); `AuthRepository.currentUser` (existing).

- [ ] **Step 1: Hold `profileRepository` as `@State`, not `let`, in `RootView`**

In `SwiftUp/App/RootView.swift`, replace:

```swift
    private let profileRepository = ProfileRepository()
```

with:

```swift
    @State private var profileRepository = ProfileRepository()
```

(Same reasoning as `questionRepository` in this file — `ProfileRepository` now owns loaded/mutable state across its lifetime, not just a static bundle decode.)

- [ ] **Step 2: Load both repositories concurrently in `TodayFlowView`, add the loading gate, record completion on finish**

Replace `SwiftUp/Features/DailyQuiz/TodayFlowView.swift` entirely:

```swift
import SwiftUI

struct TodayFlowView: View {
    enum Stage { case entry, question, summary }

    @Environment(QuestionRepository.self) private var questionRepo
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(AuthRepository.self) private var authRepo
    @State private var stage: Stage = .entry
    @State private var session: QuizSession?

    var body: some View {
        NavigationStack {
            Group {
                if questionRepo.isLoading && questionRepo.todayQuestions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.Colors.bg)
                } else {
                    switch stage {
                    case .entry:
                        DailyQuizEntryView(onBegin: startQuiz)
                    case .question:
                        if let session {
                            QuizQuestionView(session: session, onAdvance: advance)
                        }
                    case .summary:
                        if let session {
                            QuizSummaryView(session: session, onDone: finish)
                        }
                    }
                }
            }
        }
        .task {
            guard let uid = authRepo.currentUser?.uid else { return }
            async let questionsLoad: Void = questionRepo.load(for: uid)
            async let profileLoad: Void = profileRepo.load(for: uid)
            _ = await (questionsLoad, profileLoad)
        }
    }

    private func startQuiz() {
        session = QuizSession(questions: questionRepo.todayQuestions)
        stage = .question
    }

    private func advance() {
        session?.advance()
        if session?.isFinished == true {
            stage = .summary
        }
    }

    private func finish() {
        if let session, let uid = authRepo.currentUser?.uid {
            Task { await questionRepo.recordAnswered(session.questions, for: uid) }
            Task { await profileRepo.recordCompletion(session, for: uid) }
        }
        session = nil
        stage = .entry
    }
}

#Preview {
    TodayFlowView()
        .environment(ProfileRepository.preview())
        .environment(QuestionRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
```

- [ ] **Step 3: Add a loading gate to `ProfileHomeView`**

This is the one screen a user could reach (tapping the Record tab) before the launch-time `profileRepo.load(for:)` from Step 2 resolves — the other Profile subviews (`AllLevelsView`, `AccuracyByTopicView`, `BadgesView`, `MilestonesView`) are reached only by navigating from here, so gating this one screen is enough.

In `SwiftUp/Features/Profile/ProfileHomeView.swift`, find the opening of `body`:

```swift
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: repo.profile.name, right: "Top 4% this week")
```

and change it to:

```swift
    var body: some View {
        Group {
            if repo.isLoading && repo.profile.name.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.bg)
            } else {
                profileContent
            }
        }
        .background(Theme.Colors.bg)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Settings") { SettingsView() }
            }
        }
    }

    private var profileContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: repo.profile.name, right: "Top 4% this week")
```

Then find the end of the original `body` (the closing of the `ScrollView`/`VStack`, right before its own `.background`/`.navigationTitle`/`.toolbar` modifiers) — replace:

```swift
                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Settings") { SettingsView() }
            }
        }
    }
```

with (dropping the now-duplicated `.background`/`.navigationTitle`/`.toolbar`, since those moved onto the outer `Group` above):

```swift
                Spacer(minLength: 20)
            }
            .padding(24)
        }
    }
```

- [ ] **Step 4: Update every remaining `#Preview` that constructs `ProfileRepository()`**

`grep -rn "ProfileRepository()" "SwiftUp"` at this point should show only `#Preview` blocks (the app's real construction is now `RootView`'s `@State private var profileRepository = ProfileRepository()`, which is correct as-is — it deliberately uses the real, non-preview initializer since `init` itself never touches Firebase). For each of the following files, replace `.environment(ProfileRepository())` with `.environment(ProfileRepository.preview())` in its `#Preview` block:

- `SwiftUp/App/MainTabView.swift`
- `SwiftUp/Features/DailyQuiz/DailyQuizEntryView.swift`
- `SwiftUp/Features/Profile/ProfileHomeView.swift`
- `SwiftUp/Features/Profile/AccuracyByTopicView.swift`
- `SwiftUp/Features/Profile/BadgesView.swift`
- `SwiftUp/Features/Profile/MilestonesView.swift`
- `SwiftUp/Features/Profile/AllLevelsView.swift`

Example for `MainTabView.swift` — replace:

```swift
#Preview {
    MainTabView()
        .environment(QuestionRepository.preview())
        .environment(ProfileRepository())
        .environment(InterviewRepository())
        .environment(LeaderboardRepository())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
```

with:

```swift
#Preview {
    MainTabView()
        .environment(QuestionRepository.preview())
        .environment(ProfileRepository.preview())
        .environment(InterviewRepository())
        .environment(LeaderboardRepository())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
```

Apply the equivalent one-line substitution (`ProfileRepository()` → `ProfileRepository.preview()`) in each of the other six files' `#Preview` blocks — every other line in each of those blocks is unchanged.

- [ ] **Step 5: Verify build succeeds**

```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Run the full test suite**

```bash
xcodebuild test -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add SwiftUp/App/RootView.swift SwiftUp/App/MainTabView.swift SwiftUp/Features/DailyQuiz/TodayFlowView.swift SwiftUp/Features/DailyQuiz/DailyQuizEntryView.swift SwiftUp/Features/Profile/ProfileHomeView.swift SwiftUp/Features/Profile/AccuracyByTopicView.swift SwiftUp/Features/Profile/BadgesView.swift SwiftUp/Features/Profile/MilestonesView.swift SwiftUp/Features/Profile/AllLevelsView.swift
git commit -m "$(cat <<'EOF'
Load real profile/XP/streak on launch, record on quiz completion

TodayFlowView now loads QuestionRepository and ProfileRepository
concurrently and calls profileRepo.recordCompletion(_:for:) alongside
the existing recordAnswered(_:for:) when a quiz session finishes.
ProfileHomeView gates on isLoading for the one screen reachable before
that launch-time load resolves. Every #Preview needing real profile
data now uses .preview() instead, which never touches Firestore.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011chT6wfnejdTy5GNuykG51
EOF
)"
```

---

## Task 8: Final verification

**Files:** None (verification only).

- [ ] **Step 1: Full clean build + test run**

```bash
cd "/Users/thorfinn/Documents/Professional & Career material/iOS Prep App"
xcodegen generate
xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild test -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`, including the new `LevelCalculatorTests`, `StreakCalculatorTests`, `AchievementEngineTests`, and the updated `ModelDecodingTests`/`RepositoryTests`.

- [ ] **Step 2: Manual end-to-end verification (not automatable — report results, don't claim success without doing this)**

1. Build and run the app in Simulator, signed in as an existing test user (one already used against the seeded question bank from sub-project 4).
2. Note the Firebase console's `users/{uid}` values for `totalXP`, `streakDays`, `totalQuestionsAnswered` before completing a quiz (likely all absent/zero if this is the first run since this sub-project).
3. Complete a full daily quiz. Confirm in the console: `totalXP` increased by the session's XP total, `totalQuestionsAnswered` increased by 5, `streakDays` is now 1 (or incremented, if already mid-streak), `lastCompletedDate` is today, `topicStats` has entries for each answered question's topic, and a `users/{uid}/dailyCompletions/{today}` document exists with the right `correctCount`/`xpEarned`.
4. On the Profile tab, confirm the name shown matches the signed-in account's display name (not "Maya Reyes"), and that Streak/Answered/Accuracy reflect the values just confirmed in the console.
5. Complete quizzes across two more (simulated, by editing device date forward if needed) consecutive days — confirm `streakDays` increments each time and, on crossing day 7, `freezesAvailable` increases by 1.
6. Confirm at least one achievement whose criterion is now met (e.g. "Onboarded," `a09`) shows as earned in Badges, with `earnedAchievementIDs` present in the console.
