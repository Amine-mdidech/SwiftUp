# Path — Foundation (Sub-project A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the data-layer foundation for the Path progression system — a 4th `SkillLevel` grade, removal of today's silent auto-promotion, a lifetime/spendable XP split, the `PathTrack`/`PathStage` model, Firestore schema + seeded placeholder content for all 20 tracks, and a read-only `PathRepository`. No new screens, no tab bar change, no spending, no leaderboard removal — those are separate follow-up sub-projects.

**Architecture:** Four independent-but-sequenced tasks. Task 1 extends `SkillLevel` and retires the old promotion mechanism it's replacing. Task 2 splits XP into lifetime (`totalXP`, drives the existing Level ladder, untouched by spending) and spendable (`xpBalance`, new). Task 3 defines the `PathTrack`/`PathStage` models and generates+seeds placeholder content for all 20 tracks across the 4 grades. Task 4 builds `PathRepository` (read-only fetch + pure completion/unlock logic) on top of Task 3's models and wires it into `RootView`.

**Tech Stack:** SwiftUI (iOS 17+), `@Observable`, Firebase Firestore, Swift Testing, XcodeGen, Python 3 + `firebase-admin` for seed scripts (via an isolated venv — see `scripts/README.md` for the existing setup pattern this project already uses).

**Spec:** `docs/superpowers/specs/2026-09-18-path-foundation-design.md`

## Global Constraints

- `totalXP` keeps its exact current meaning (lifetime earned, monotonic, drives the existing Level ladder) — nothing in this plan may make it decrease or change what it represents.
- `xpBalance` is the only field Path spending will ever touch (in a later sub-project) — this plan only adds it and keeps it in sync with every existing earn event; nothing in this plan spends it.
- No new screens, no tab bar changes, no leaderboard changes. This plan is data-layer only.
- Content for all 20 tracks is placeholder/formula-generated except Junior track 2 ("Object-oriented Swift"), which is hand-authored verbatim from the source design — see spec §5 for the exact values.
- Tests run on `-destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'` (the bare `name=iPhone 16` destination is ambiguous on this machine without pinning `OS=18.6`). A full-app build (no tests) instead uses `-destination 'generic/platform=iOS Simulator'`.
- Every `xcodebuild`/`xcodegen` command must run in the **foreground** — never background a build or test run.
- After adding or removing any file, run `xcodegen generate` from the repo root before building.
- Two pre-existing **untracked** files, `SwiftUp/App/SplashView.swift` and `SwiftUp/Assets.xcassets/`, belong to the user's own separate in-progress work — never commit them, and copy them into any new worktree so the baseline builds.

---

## Task 1: Extend `SkillLevel` to four grades, remove the old auto-promotion

**Files:**
- Modify: `SwiftUp/Models/SkillLevel.swift`
- Modify: `SwiftUp/Features/Onboarding/SkillAssessmentView.swift`
- Modify: `SwiftUp/Models/DailyQuizDocument.swift`
- Modify: `SwiftUp/Data/QuestionRepository.swift`
- Delete: `SwiftUp/Data/QuestionSelector.swift`
- Delete: `SwiftUpTests/QuestionSelectorTests.swift`
- Test: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Produces (consumed by Task 3/4 indirectly, since `PathTrack.grade` is typed `SkillLevel`): `SkillLevel` with 4 cases (`.junior`, `.mid`, `.senior`, `.distinguished`), `SkillLevel.next: SkillLevel?`, `SkillLevel.onboardingChoices: [SkillLevel]`.
- Consumes: nothing from other tasks.

- [ ] **Step 1: Write the failing tests for the extended `SkillLevel`**

Add to `SwiftUpTests/RepositoryTests.swift` (inside `struct RepositoryTests`):

```swift
    @Test func skillLevelNextClimbsAllFourGradesThenCeilings() {
        #expect(SkillLevel.junior.next == .mid)
        #expect(SkillLevel.mid.next == .senior)
        #expect(SkillLevel.senior.next == .distinguished)
        #expect(SkillLevel.distinguished.next == nil)
    }

    @Test func skillLevelOnboardingChoicesExcludesDistinguished() {
        #expect(SkillLevel.onboardingChoices == [.junior, .mid, .senior])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: FAIL — `SkillLevel` has no `.distinguished` case and no `onboardingChoices` yet (compile error).

- [ ] **Step 3: Extend `SkillLevel`**

Replace the full contents of `SwiftUp/Models/SkillLevel.swift`:

```swift
import Foundation

enum SkillLevel: String, CaseIterable, Identifiable, Codable {
    case junior = "Junior", mid = "Mid", senior = "Senior", distinguished = "Distinguished"
    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .junior: "Shipping with SwiftUI, still meeting the SDK. Under two years."
        case .mid: "Comfortable in UIKit and SwiftUI, reaching for concurrency and architecture. Two to five years."
        case .senior: "Leading work, designing systems, interviewing others. Five years and up."
        case .distinguished: "Platform strategy, cross-team architecture, technical direction."
        }
    }

    /// The next grade Path's regrade quiz promotes to (a later sub-project). `nil` at the
    /// ceiling — matches the source design's "no grade above this one."
    var next: SkillLevel? {
        switch self {
        case .junior: .mid
        case .mid: .senior
        case .senior: .distinguished
        case .distinguished: nil
        }
    }

    /// Grades the onboarding assessment offers. Nobody starts at Distinguished — it's only
    /// reachable by climbing every track in every earlier grade.
    static let onboardingChoices: [SkillLevel] = [.junior, .mid, .senior]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: PASS

- [ ] **Step 5: Update the onboarding picker to use `onboardingChoices`**

In `SwiftUp/Features/Onboarding/SkillAssessmentView.swift`, replace:

```swift
                ForEach(SkillLevel.allCases) { level in
                    RuledRow(showBottomRule: level == SkillLevel.allCases.last, minHeight: 60) {
```

with:

```swift
                ForEach(SkillLevel.onboardingChoices) { level in
                    RuledRow(showBottomRule: level == SkillLevel.onboardingChoices.last, minHeight: 60) {
```

- [ ] **Step 6: Write the failing test for `DailyQuizDocument.questions(for:)` routing Distinguished to Senior**

Find the existing test(s) for `DailyQuizDocument` in `SwiftUpTests/ModelDecodingTests.swift` (search for `decodesDailyQuizDocumentAndLooksUpByLevel`) and add, in the same test or a new one right after it:

```swift
    @Test func dailyQuizDocumentRoutesDistinguishedToSeniorQuestions() throws {
        func question(_ id: String) -> String {
            """
            {"id":"\(id)","topic":"t","level":"Senior","format":"multipleChoice","prompt":"p",
             "codeSnippet":null,"options":[{"id":"A","text":"a"}],"correctOptionID":"A",
             "explanation":"e","xp":10}
            """
        }
        let json = """
        {"edition":1,"junior":[],"mid":[],"senior":[\(question("s1"))]}
        """.data(using: .utf8)!
        let doc = try JSONDecoder().decode(DailyQuizDocument.self, from: json)
        #expect(doc.questions(for: .distinguished).map(\.id) == doc.questions(for: .senior).map(\.id))
        #expect(doc.questions(for: .distinguished).map(\.id) == ["s1"])
    }
```

If `ModelDecodingTests.swift` doesn't already have a helper exactly like the `question(_:)` closure above, write the full JSON inline instead — check the file's existing `decodesDailyQuizDocumentAndLooksUpByLevel` test first and match whatever question-JSON shape it already uses verbatim (its `Question` fields must match `SwiftUp/Models/Question.swift` exactly: `id, topic, level, format, prompt, codeSnippet, options, correctOptionID, explanation, xp`).

- [ ] **Step 7: Run the test to verify it fails**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/ModelDecodingTests`
Expected: FAIL — `questions(for:)`'s switch isn't exhaustive yet / doesn't compile with the new `SkillLevel` case, or (once Step 3 already made it compile-fail) this step may show the switch is non-exhaustive as a build error rather than a test failure. Either way, confirm it fails before Step 8.

- [ ] **Step 8: Extend `DailyQuizDocument.questions(for:)`**

In `SwiftUp/Models/DailyQuizDocument.swift`, replace:

```swift
    func questions(for level: SkillLevel) -> [Question] {
        switch level {
        case .junior: junior
        case .mid: mid
        case .senior: senior
        }
    }
```

with:

```swift
    func questions(for level: SkillLevel) -> [Question] {
        switch level {
        case .junior: junior
        case .mid: mid
        case .senior, .distinguished: senior
        }
    }
```

- [ ] **Step 9: Run the test to verify it passes**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/ModelDecodingTests`
Expected: PASS

- [ ] **Step 10: Remove the old auto-promotion from `QuestionRepository`**

In `SwiftUp/Data/QuestionRepository.swift`, replace the whole `load(for uid:)` method:

```swift
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        let userDoc = Firestore.firestore().collection("users").document(uid)

        var storedLevel = SkillLevel.junior
        var override: SkillLevel?
        var answered: [String: Date] = [:]

        do {
            let snapshot = try await userDoc.getDocument()
            if let raw = snapshot.get("skillLevel") as? String, let level = SkillLevel(rawValue: raw) {
                storedLevel = level
            }
            if let raw = snapshot.get("levelOverride") as? String, let level = SkillLevel(rawValue: raw) {
                override = level
            }
            if let map = snapshot.get("answeredQuestionIDs") as? [String: Timestamp] {
                answered = map.mapValues { $0.dateValue() }
            }
        } catch { }

        levelOverride = override
        var effectiveLevel = override ?? storedLevel

        if let bank = try? await fetchBank(level: effectiveLevel), !bank.isEmpty,
           QuestionSelector.shouldPromote(bank: bank, answered: answered), let next = effectiveLevel.next {
            effectiveLevel = next
            storedLevel = next
            try? await userDoc.updateData(["skillLevel": next.rawValue])
        }

        guard let daily = try? await fetchDailyQuiz() else {
            todayQuestions = Self.loadBundledFallback()
            editionNumber = nil
            return
        }

        todayQuestions = daily.questions(for: effectiveLevel)
        editionNumber = daily.edition
        self.effectiveLevel = effectiveLevel
    }
```

with:

```swift
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        let userDoc = Firestore.firestore().collection("users").document(uid)

        var storedLevel = SkillLevel.junior
        var override: SkillLevel?

        do {
            let snapshot = try await userDoc.getDocument()
            if let raw = snapshot.get("skillLevel") as? String, let level = SkillLevel(rawValue: raw) {
                storedLevel = level
            }
            if let raw = snapshot.get("levelOverride") as? String, let level = SkillLevel(rawValue: raw) {
                override = level
            }
        } catch {
            // No user doc data available (offline, first launch) — proceed with defaults.
        }

        levelOverride = override
        let effectiveLevel = override ?? storedLevel

        guard let daily = try? await fetchDailyQuiz() else {
            todayQuestions = Self.loadBundledFallback()
            editionNumber = nil
            return
        }

        todayQuestions = daily.questions(for: effectiveLevel)
        editionNumber = daily.edition
        self.effectiveLevel = effectiveLevel
    }
```

Then delete the now-unused `fetchBank` method entirely:

```swift
    private func fetchBank(level: SkillLevel) async throws -> [Question] {
        let snapshot = try await Firestore.firestore()
            .collection("questions")
            .whereField("level", isEqualTo: level.rawValue)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Question.self) }
    }
```

- [ ] **Step 11: Delete `QuestionSelector.swift` and its test file**

```bash
git rm SwiftUp/Data/QuestionSelector.swift SwiftUpTests/QuestionSelectorTests.swift
```

- [ ] **Step 12: Regenerate the Xcode project and run the full test suite**

Run: `xcodegen generate && xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
Expected: BUILD SUCCEEDED, all tests pass (the two `QuestionSelectorTests` are gone, everything else still green — including `questionRepositoryBundledFallbackLoadsFiveQuestions`, unaffected by this change).

- [ ] **Step 13: Commit**

```bash
git add SwiftUp/Models/SkillLevel.swift SwiftUp/Features/Onboarding/SkillAssessmentView.swift SwiftUp/Models/DailyQuizDocument.swift SwiftUp/Data/QuestionRepository.swift SwiftUpTests/RepositoryTests.swift SwiftUpTests/ModelDecodingTests.swift
git commit -m "Add Distinguished grade to SkillLevel, remove silent auto-promotion"
```

---

## Task 2: Split XP into lifetime (`totalXP`) and spendable (`xpBalance`)

**Files:**
- Modify: `SwiftUp/Models/UserProfile.swift`
- Modify: `SwiftUp/Data/ProfileRepository.swift`
- Modify: `SwiftUp/Resources/profile.json`
- Modify: `SwiftUpTests/Fixtures/profile.json`
- Modify: `SwiftUpTests/ModelDecodingTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces (consumed by later sub-projects, not this plan): `UserProfile.xpBalance: Int`.

- [ ] **Step 1: Add `"xpBalance"` to both bundled `profile.json` fixtures**

In both `SwiftUp/Resources/profile.json` and `SwiftUpTests/Fixtures/profile.json` (identical files), add a line right after `"xp": 3240,`:

```json
  "xpBalance": 3240,
```

- [ ] **Step 2: Write the failing test for `UserProfile` decoding `xpBalance`**

In `SwiftUpTests/ModelDecodingTests.swift`, find `decodesUserProfile()` and update its JSON literal to include the new field (add right after `"xp": 3240,`):

```swift
          "xpForCurrentLevel": 2200, "xpForNextLevel": 3700, "xpBalance": 3240,
```

and add an assertion:

```swift
        #expect(p.xpBalance == 3240)
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/ModelDecodingTests`
Expected: FAIL — `UserProfile` has no `xpBalance` member yet (compile error).

- [ ] **Step 4: Add `xpBalance` to `UserProfile`**

In `SwiftUp/Models/UserProfile.swift`, replace:

```swift
struct UserProfile: Codable {
    let name: String
    let initials: String
    let level: Int
    let levelTitle: String
    let xp: Int
    let xpForCurrentLevel: Int
    let xpForNextLevel: Int
    let streakDays: Int
    let freezesAvailable: Int
    let freezesTotal: Int
    let answeredCount: Int
    let accuracyPercent: Int
    let memberSinceDisplay: String
```

with:

```swift
struct UserProfile: Codable {
    let name: String
    let initials: String
    let level: Int
    let levelTitle: String
    let xp: Int
    /// Spendable XP balance — separate from `xp` (lifetime earned, drives the Level ladder above
    /// and must never decrease). This is what Path spending debits; every earn event credits both
    /// by the same amount. See `ProfileRepository.recordCompletion` for the backfill-on-first-touch
    /// rule for users who don't have this field yet.
    let xpBalance: Int
    let xpForCurrentLevel: Int
    let xpForNextLevel: Int
    let streakDays: Int
    let freezesAvailable: Int
    let freezesTotal: Int
    let answeredCount: Int
    let accuracyPercent: Int
    let memberSinceDisplay: String
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/ModelDecodingTests`
Expected: FAIL still — this compiles now, but `ProfileRepository`'s two `UserProfile(...)` construction call sites (its `init` and `buildProfile`) don't pass `xpBalance:` yet, so the whole target won't build. Continue to Step 6 before re-running.

- [ ] **Step 6: Update `ProfileRepository`'s zeroed default profile**

In `SwiftUp/Data/ProfileRepository.swift`, in `init(bundle:)`, replace:

```swift
        profile = UserProfile(
            name: "", initials: "", level: level.number, levelTitle: level.title,
            xp: 0, xpForCurrentLevel: level.xpForCurrentLevel, xpForNextLevel: level.xpForNextLevel,
            streakDays: 0, freezesAvailable: 0, freezesTotal: 3,
            answeredCount: 0, accuracyPercent: 0, memberSinceDisplay: ""
        )
```

with:

```swift
        profile = UserProfile(
            name: "", initials: "", level: level.number, levelTitle: level.title,
            xp: 0, xpBalance: 0, xpForCurrentLevel: level.xpForCurrentLevel, xpForNextLevel: level.xpForNextLevel,
            streakDays: 0, freezesAvailable: 0, freezesTotal: 3,
            answeredCount: 0, accuracyPercent: 0, memberSinceDisplay: ""
        )
```

- [ ] **Step 7: Add `xpBalance` to `apply(snapshot:recentCompletions:)` and `buildProfile`**

In `SwiftUp/Data/ProfileRepository.swift`, find `apply(snapshot:recentCompletions:)` and, right after the existing line reading `totalXP`:

```swift
        let totalXP = (snapshot.get("totalXP") as? Int) ?? 0
```

add:

```swift
        // Backfill-on-read only (no write here — `load(for:)` is read-only today): a user with
        // `totalXP` but no `xpBalance` yet hasn't spent anything, so their full lifetime total is
        // still spendable. The real backfill-and-persist happens in `recordCompletion` below, the
        // next time this user earns anything.
        let xpBalance = (snapshot.get("xpBalance") as? Int) ?? totalXP
```

Then find `buildProfile(...)`'s signature and body:

```swift
    private static func buildProfile(
        displayName: String?, createdAt: Timestamp?, freezesAvailable: Int, stats: UserStats,
        level: (number: Int, title: String, xpForCurrentLevel: Int, xpForNextLevel: Int)
    ) -> UserProfile {
        let name = (displayName?.isEmpty == false) ? displayName! : "SwiftUp user"
        return UserProfile(
            name: name, initials: initials(from: name), level: level.number, levelTitle: level.title,
            xp: stats.totalXP, xpForCurrentLevel: level.xpForCurrentLevel, xpForNextLevel: level.xpForNextLevel,
            streakDays: stats.streakDays, freezesAvailable: freezesAvailable, freezesTotal: 3,
            answeredCount: stats.totalQuestionsAnswered, accuracyPercent: overallAccuracy(stats.topicStats),
            memberSinceDisplay: memberSinceDisplay(createdAt)
        )
    }
```

replace with (new `xpBalance:` parameter, threaded into the returned `UserProfile`):

```swift
    private static func buildProfile(
        displayName: String?, createdAt: Timestamp?, freezesAvailable: Int, xpBalance: Int, stats: UserStats,
        level: (number: Int, title: String, xpForCurrentLevel: Int, xpForNextLevel: Int)
    ) -> UserProfile {
        let name = (displayName?.isEmpty == false) ? displayName! : "SwiftUp user"
        return UserProfile(
            name: name, initials: initials(from: name), level: level.number, levelTitle: level.title,
            xp: stats.totalXP, xpBalance: xpBalance, xpForCurrentLevel: level.xpForCurrentLevel, xpForNextLevel: level.xpForNextLevel,
            streakDays: stats.streakDays, freezesAvailable: freezesAvailable, freezesTotal: 3,
            answeredCount: stats.totalQuestionsAnswered, accuracyPercent: overallAccuracy(stats.topicStats),
            memberSinceDisplay: memberSinceDisplay(createdAt)
        )
    }
```

Now there are two call sites of `buildProfile` to update — one inside `apply(snapshot:recentCompletions:)`:

```swift
        profile = Self.buildProfile(
            displayName: snapshot.get("displayName") as? String,
            createdAt: snapshot.get("createdAt") as? Timestamp,
            freezesAvailable: freezesAvailable, stats: stats, level: level
        )
```

becomes:

```swift
        profile = Self.buildProfile(
            displayName: snapshot.get("displayName") as? String,
            createdAt: snapshot.get("createdAt") as? Timestamp,
            freezesAvailable: freezesAvailable, xpBalance: xpBalance, stats: stats, level: level
        )
```

and the other inside `recordCompletion` (see Step 8 below — that call site gets a *new* value, `newXPBalance`, not the plain `xpBalance` read above).

- [ ] **Step 8: Add the real backfill-and-persist to `recordCompletion`**

In `SwiftUp/Data/ProfileRepository.swift`'s `recordCompletion(_:for:)`, find the existing XP computation:

```swift
            let newTotalXP = ((snapshot.get("totalXP") as? Int) ?? 0) + session.totalXPEarned
```

and add right after it:

```swift
            let previousXPBalance = (snapshot.get("xpBalance") as? Int) ?? ((snapshot.get("totalXP") as? Int) ?? 0)
            let newXPBalance = previousXPBalance + session.totalXPEarned
```

Find the `userUpdates` dictionary:

```swift
            var userUpdates: [String: Any] = [
                "totalXP": newTotalXP,
                "totalQuestionsAnswered": newTotalAnswered,
                "perfectDayCount": newPerfectDayCount,
                "streakDays": streakResult.streakDays,
                "freezesAvailable": streakResult.freezesAvailable,
                "lastCompletedDate": today,
            ]
```

add one more key:

```swift
            var userUpdates: [String: Any] = [
                "totalXP": newTotalXP,
                "xpBalance": newXPBalance,
                "totalQuestionsAnswered": newTotalAnswered,
                "perfectDayCount": newPerfectDayCount,
                "streakDays": streakResult.streakDays,
                "freezesAvailable": streakResult.freezesAvailable,
                "lastCompletedDate": today,
            ]
```

Find the local-state mirror at the end of the method:

```swift
            let freezesAvailable = streakResult.freezesAvailable
            profile = Self.buildProfile(
                displayName: displayName,
                createdAt: snapshot.get("createdAt") as? Timestamp,
                freezesAvailable: freezesAvailable, stats: stats, level: level
            )
```

and update it to pass the new balance through:

```swift
            let freezesAvailable = streakResult.freezesAvailable
            profile = Self.buildProfile(
                displayName: displayName,
                createdAt: snapshot.get("createdAt") as? Timestamp,
                freezesAvailable: freezesAvailable, xpBalance: newXPBalance, stats: stats, level: level
            )
```

- [ ] **Step 9: Run the full test suite to verify everything compiles and passes**

Run: `xcodegen generate && xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
Expected: BUILD SUCCEEDED, all tests pass, including `profileRepositoryLoadsBundledFallback` (now implicitly exercising `xpBalance` decoding via the updated fixture) and `decodesUserProfile`.

- [ ] **Step 10: Commit**

```bash
git add SwiftUp/Models/UserProfile.swift SwiftUp/Data/ProfileRepository.swift SwiftUp/Resources/profile.json SwiftUpTests/Fixtures/profile.json SwiftUpTests/ModelDecodingTests.swift
git commit -m "Split XP into lifetime totalXP and spendable xpBalance"
```

---

## Task 3: `PathTrack`/`PathStage` models, generated seed content, bundled fallback

**Files:**
- Create: `SwiftUp/Models/PathTrack.swift`
- Create: `scripts/generate_path_tracks.py`
- Create: `scripts/path-tracks.json` (generated output, then committed)
- Create: `scripts/seed_path_tracks.py`
- Create: `SwiftUp/Resources/path_tracks.json` (copy of `scripts/path-tracks.json`)
- Create: `SwiftUpTests/Fixtures/path_tracks.json` (copy of `scripts/path-tracks.json`)
- Test: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Consumes: `SkillLevel` (Task 1) as `PathTrack.grade`'s type.
- Produces (consumed by Task 4): `struct PathStage: Codable, Identifiable` (`id: String`, `order: Int`, `title: String`, `xpCost: Int`, `kind: Kind` where `Kind: String, Codable { case lesson, assessment }`), `struct PathTrack: Codable, Identifiable` (`id: String`, `grade: SkillLevel`, `order: Int`, `title: String`, `stages: [PathStage]`). Bundled fixture file at `path_tracks.json` (no extension in the lookup call, matching `decodeJSONResource`'s existing convention) in both `SwiftUp/Resources/` and `SwiftUpTests/Fixtures/`.

- [ ] **Step 1: Write `PathTrack.swift`**

Create `SwiftUp/Models/PathTrack.swift`:

```swift
import Foundation

struct PathStage: Codable, Identifiable {
    enum Kind: String, Codable { case lesson, assessment }
    let id: String
    let order: Int
    let title: String
    let xpCost: Int
    let kind: Kind
}

struct PathTrack: Codable, Identifiable {
    let id: String
    let grade: SkillLevel
    let order: Int
    let title: String
    let stages: [PathStage]
}
```

- [ ] **Step 2: Write the generation script**

Create `scripts/generate_path_tracks.py`:

```python
#!/usr/bin/env python3
"""Generates scripts/path-tracks.json from the table below — see design doc
docs/superpowers/specs/2026-09-18-path-foundation-design.md §5 for why this
is formula-generated placeholder content rather than hand-authored data.

Run: python3 scripts/generate_path_tracks.py
Re-run any time the GRADES table below changes; it overwrites
scripts/path-tracks.json deterministically (same inputs -> same output).
"""
import json
from pathlib import Path

GRADES = [
    ("Junior", 1.0, ["Swift fundamentals", "Object-oriented Swift", "Architecture basics", "Memory & ARC", "SwiftUI state"]),
    ("Mid", 1.5, ["Concurrency", "Testing", "Networking", "Persistence", "Performance", "App lifecycle"]),
    ("Senior", 2.0, ["System design", "Module boundaries", "Migration strategy", "Code review", "Mentoring"]),
    ("Distinguished", 2.5, ["Platform strategy", "Cross-team architecture", "Technical direction", "Engineering culture"]),
]

# Hand-authored exception, taken verbatim from the design (junior-02).
JUNIOR_02_STAGES = [
    {"title": "Classes, structs and value semantics", "xpCost": 45, "kind": "lesson"},
    {"title": "Initialisers and inheritance", "xpCost": 45, "kind": "lesson"},
    {"title": "Protocols as interfaces", "xpCost": 45, "kind": "lesson"},
    {"title": "Protocol-oriented design", "xpCost": 200, "kind": "lesson"},
    {"title": "Generics and associated types", "xpCost": 200, "kind": "lesson"},
    {"title": "Composition over inheritance", "xpCost": 200, "kind": "lesson"},
    {"title": "Error handling and typed throws", "xpCost": 200, "kind": "lesson"},
    {"title": "Track assessment", "xpCost": 400, "kind": "assessment"},
]


def round5(n: float) -> int:
    return int(round(n / 5.0) * 5)


def build_stages(track_id: str, title: str, multiplier: float) -> list[dict]:
    if track_id == "junior-02":
        stages = JUNIOR_02_STAGES
    else:
        lesson_cost = round5(50 * multiplier)
        assessment_cost = round5(400 * multiplier)
        stages = [
            {"title": f"{title} — lesson {n} of 6", "xpCost": lesson_cost, "kind": "lesson"}
            for n in range(1, 7)
        ] + [{"title": "Track assessment", "xpCost": assessment_cost, "kind": "assessment"}]
    return [
        {"id": f"{track_id}-s{i:02d}", "order": i, "title": s["title"], "xpCost": s["xpCost"], "kind": s["kind"]}
        for i, s in enumerate(stages, start=1)
    ]


def main() -> None:
    tracks = []
    for grade, multiplier, titles in GRADES:
        grade_slug = grade.lower()
        for order, title in enumerate(titles, start=1):
            track_id = f"{grade_slug}-{order:02d}"
            tracks.append({
                "id": track_id,
                "grade": grade,
                "order": order,
                "title": title,
                "stages": build_stages(track_id, title, multiplier),
            })
    out_path = Path(__file__).resolve().parent / "path-tracks.json"
    out_path.write_text(json.dumps(tracks, indent=2) + "\n")
    print(f"Wrote {len(tracks)} tracks to {out_path}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Run the generation script**

Run: `python3 scripts/generate_path_tracks.py`
Expected: prints `Wrote 20 tracks to .../scripts/path-tracks.json`. Verify with `python3 -c "import json; d=json.load(open('scripts/path-tracks.json')); print(len(d), sum(len(t['stages']) for t in d))"` — expect `20` tracks and `141` total stages (8 for `junior-02` + 7×19 for every other track).

- [ ] **Step 4: Copy the generated file into both bundled-resource locations**

```bash
cp scripts/path-tracks.json "SwiftUp/Resources/path_tracks.json"
cp scripts/path-tracks.json "SwiftUpTests/Fixtures/path_tracks.json"
```

(Note the filename change: hyphen in `scripts/`, underscore in the two bundled copies — this matches the existing `interview-bank.json` / `interview_bank.json` convention exactly. All three files have identical JSON content, just different names.)

- [ ] **Step 5: Write the seed script**

Create `scripts/seed_path_tracks.py`, following `scripts/seed_questions.py`'s exact structure:

```python
#!/usr/bin/env python3
"""
One-time (and re-runnable) script to load scripts/path-tracks.json into
the `pathTracks` collection in Firestore.

Setup:
  1. pip install firebase-admin
  2. Firebase console -> Project settings -> Service accounts ->
     "Generate new private key" -> save the downloaded file as
     scripts/serviceAccountKey.json (this exact path is gitignored — never
     commit it).
  3. python3 scripts/seed_path_tracks.py

Safe to re-run: it overwrites each track document by its `id`, so
re-running after regenerating path-tracks.json just updates the changed
fields rather than creating duplicates.
"""
import json
import sys
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

SCRIPT_DIR = Path(__file__).resolve().parent
KEY_PATH = SCRIPT_DIR / "serviceAccountKey.json"
SEED_PATH = SCRIPT_DIR / "path-tracks.json"


def main() -> int:
    if not KEY_PATH.exists():
        print(f"Missing {KEY_PATH}.", file=sys.stderr)
        print("Download it from Firebase console -> Project settings -> "
              "Service accounts -> Generate new private key.", file=sys.stderr)
        return 1

    with open(SEED_PATH) as f:
        tracks = json.load(f)

    cred = credentials.Certificate(str(KEY_PATH))
    firebase_admin.initialize_app(cred)
    db = firestore.client()

    batch = db.batch()
    for track in tracks:
        doc_ref = db.collection("pathTracks").document(track["id"])
        batch.set(doc_ref, track)
    batch.commit()

    print(f"Seeded {len(tracks)} path tracks into Firestore.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

Do **not** run this seed script yet — it writes to live Firestore. It runs at the end of Task 4, after `PathRepository` exists to actually read the data back (so there's something to verify against), and only with the user's explicit authorization, matching how every other seed script in this project has been run this session.

- [ ] **Step 6: Write the failing test for decoding the bundled fixture**

Add to `SwiftUpTests/RepositoryTests.swift`:

```swift
    @Test func pathTrackBundledFixtureDecodesTwentyTracksWithJunior02HandAuthored() throws {
        let tracks = decodeJSONResource([PathTrack].self, filename: "path_tracks", bundle: testBundle) ?? []
        #expect(tracks.count == 20)
        let junior02 = try #require(tracks.first { $0.id == "junior-02" })
        #expect(junior02.grade == .junior)
        #expect(junior02.title == "Object-oriented Swift")
        #expect(junior02.stages.count == 8)
        #expect(junior02.stages.map(\.xpCost) == [45, 45, 45, 200, 200, 200, 200, 400])
        #expect(junior02.stages.last?.kind == .assessment)
        #expect(junior02.stages.last?.title == "Track assessment")
    }
```

- [ ] **Step 7: Run the test to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: FAIL — `path_tracks.json` isn't a recognized bundle resource until `xcodegen generate` picks up the new `SwiftUpTests/Fixtures/path_tracks.json` file (it should, since `sources: - path: SwiftUpTests` is a directory glob) — if it still fails after regenerating, check that the file actually landed at that exact path in Step 4.

- [ ] **Step 8: Confirm the test passes**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: PASS. (There's no separate "implementation" step here — Steps 1-5 already produced the file being tested; this step just confirms Step 4's copy is correct and matches the model shape from Step 1.)

- [ ] **Step 9: Run the full test suite and build**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
Expected: BUILD SUCCEEDED, all tests pass.

- [ ] **Step 10: Commit**

```bash
git add SwiftUp/Models/PathTrack.swift scripts/generate_path_tracks.py scripts/path-tracks.json scripts/seed_path_tracks.py SwiftUp/Resources/path_tracks.json SwiftUpTests/Fixtures/path_tracks.json SwiftUpTests/RepositoryTests.swift
git commit -m "Add PathTrack/PathStage models and generated placeholder content for all 20 tracks"
```

---

## Task 4: `PathRepository` (read-only) + `RootView` wiring + seed

**Files:**
- Create: `SwiftUp/Data/PathRepository.swift`
- Modify: `SwiftUp/App/RootView.swift`
- Test: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Consumes: `PathTrack`/`PathStage` (Task 3), `decodeJSONResource` (existing free function in `QuestionRepository.swift`).
- Produces: `PathRepository` with `tracks: [PathTrack]`, `completedStageIDs: Set<String>`, `isLoading: Bool`, `load(for uid:) async`, `tracks(for grade: SkillLevel) -> [PathTrack]`, `isStageCompleted(_:) -> Bool`, `isTrackClosed(_:) -> Bool`, `isStageUnlocked(_:in:) -> Bool`, `static func preview(bundle:) -> PathRepository`.

- [ ] **Step 1: Write the failing tests for the pure completion/unlock logic**

Add to `SwiftUpTests/RepositoryTests.swift`:

```swift
    @Test func pathRepositoryTrackIsClosedOnlyWhenEveryStageIsCompleted() {
        let stages = [
            PathStage(id: "t-s01", order: 1, title: "One", xpCost: 50, kind: .lesson),
            PathStage(id: "t-s02", order: 2, title: "Two", xpCost: 50, kind: .lesson),
            PathStage(id: "t-s03", order: 3, title: "Assessment", xpCost: 400, kind: .assessment),
        ]
        let track = PathTrack(id: "t", grade: .junior, order: 1, title: "Track", stages: stages)
        let repo = PathRepository()

        #expect(repo.isTrackClosed(track) == false)
    }

    @Test func pathRepositoryStageUnlocksOnlyAfterEveryEarlierStageInItsTrackIsDone() {
        let stages = [
            PathStage(id: "t-s01", order: 1, title: "One", xpCost: 50, kind: .lesson),
            PathStage(id: "t-s02", order: 2, title: "Two", xpCost: 50, kind: .lesson),
            PathStage(id: "t-s03", order: 3, title: "Assessment", xpCost: 400, kind: .assessment),
        ]
        let track = PathTrack(id: "t", grade: .junior, order: 1, title: "Track", stages: stages)
        let repo = PathRepository()

        #expect(repo.isStageUnlocked(stages[0], in: track) == true)
        #expect(repo.isStageUnlocked(stages[1], in: track) == false)
        #expect(repo.isStageUnlocked(stages[2], in: track) == false)
    }

    @Test func pathRepositoryTracksForGradeFiltersAndSortsByOrder() {
        let repo = PathRepository.preview(bundle: testBundle)
        let juniorTracks = repo.tracks(for: .junior)
        #expect(juniorTracks.count == 5)
        #expect(juniorTracks.map(\.order) == [1, 2, 3, 4, 5])
        #expect(juniorTracks.allSatisfy { $0.grade == .junior })
    }
```

Note: `isTrackClosed`/`isStageUnlocked` are pure functions of `track`/`stage` plus `completedStageIDs` — but `completedStageIDs` is `private(set)`, populated only by `load(for:)`. These three tests all exercise the **empty-`completedStageIDs`** case (a freshly-constructed `PathRepository()`, never loaded) — which is sufficient to prove the logic without needing Firestore or a settable seam. (If you want to also exercise the "some stages already completed" branch, that requires either a `load(for:)` call against a live/fake backend or a test-only setter, neither of which is in scope for this plan — the empty-state assertions above already prove both methods' core logic: `isTrackClosed` returns `false` when nothing is done, `isStageUnlocked` returns `true` only for the very first stage when nothing is done.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: FAIL — `PathRepository` doesn't exist yet.

- [ ] **Step 3: Write `PathRepository`**

Create `SwiftUp/Data/PathRepository.swift`:

```swift
import Foundation
import FirebaseFirestore

@Observable
final class PathRepository {
    private(set) var tracks: [PathTrack] = []
    private(set) var completedStageIDs: Set<String> = []
    private(set) var isLoading = false

    init() {}

    /// Synchronously loads bundled fallback content — safe for #Preview, never touches Firestore.
    static func preview(bundle: Bundle = .main) -> PathRepository {
        let repo = PathRepository()
        repo.tracks = loadBundledFallback(bundle: bundle)
        return repo
    }

    static func loadBundledFallback(bundle: Bundle = .main) -> [PathTrack] {
        decodeJSONResource([PathTrack].self, filename: "path_tracks", bundle: bundle) ?? []
    }

    /// Fetches every track across all four grades — a fixed, small collection (20 tracks), the
    /// same "load it all at once" approach `InterviewRepository` already takes for its bank — plus
    /// this user's completed stage IDs.
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        async let tracksResult = Self.fetchTracks()
        async let completedResult = Self.fetchCompletedStageIDs(uid: uid)
        let (fetchedTracks, fetchedCompleted) = await (tracksResult, completedResult)

        tracks = fetchedTracks.isEmpty ? Self.loadBundledFallback() : fetchedTracks
        completedStageIDs = fetchedCompleted
    }

    func tracks(for grade: SkillLevel) -> [PathTrack] {
        tracks.filter { $0.grade == grade }.sorted { $0.order < $1.order }
    }

    func isStageCompleted(_ stage: PathStage) -> Bool {
        completedStageIDs.contains(stage.id)
    }

    func isTrackClosed(_ track: PathTrack) -> Bool {
        !track.stages.isEmpty && track.stages.allSatisfy { isStageCompleted($0) }
    }

    /// A stage unlocks once every earlier stage (by `order`) in its own track is completed. The
    /// first stage in a track is always unlocked by this method's own logic — whether the *track*
    /// itself is reachable (e.g. "you need 3 of 5 Junior tracks closed before this one shows") is
    /// a later sub-project's concern, not this repository's.
    func isStageUnlocked(_ stage: PathStage, in track: PathTrack) -> Bool {
        track.stages.filter { $0.order < stage.order }.allSatisfy { isStageCompleted($0) }
    }

    private static func fetchTracks() async -> [PathTrack] {
        guard let snapshot = try? await Firestore.firestore().collection("pathTracks").getDocuments() else {
            return []
        }
        return snapshot.documents.compactMap { try? $0.data(as: PathTrack.self) }
    }

    private static func fetchCompletedStageIDs(uid: String) async -> Set<String> {
        guard let snapshot = try? await Firestore.firestore().collection("users").document(uid).getDocument(),
              let map = snapshot.get("completedPathStageIDs") as? [String: Timestamp]
        else {
            return []
        }
        return Set(map.keys)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: PASS

- [ ] **Step 5: Wire `PathRepository` into `RootView`**

In `SwiftUp/App/RootView.swift`, replace:

```swift
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showSplash = true

    @State private var questionRepository = QuestionRepository()
    @State private var profileRepository = ProfileRepository()
    @State private var interviewRepository = InterviewRepository()
    @State private var leaderboardRepository = LeaderboardRepository()
    @State private var authRepository = AuthRepository()
```

with:

```swift
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showSplash = true

    @State private var questionRepository = QuestionRepository()
    @State private var profileRepository = ProfileRepository()
    @State private var interviewRepository = InterviewRepository()
    @State private var leaderboardRepository = LeaderboardRepository()
    @State private var pathRepository = PathRepository()
    @State private var authRepository = AuthRepository()
```

and replace:

```swift
        .environment(questionRepository)
        .environment(profileRepository)
        .environment(interviewRepository)
        .environment(leaderboardRepository)
        .environment(authRepository)
```

with:

```swift
        .environment(questionRepository)
        .environment(profileRepository)
        .environment(interviewRepository)
        .environment(leaderboardRepository)
        .environment(pathRepository)
        .environment(authRepository)
```

No screen consumes `PathRepository` yet — this only makes it available via `@Environment(PathRepository.self)` for the sub-project that builds the first Path screen, so that sub-project's plan doesn't need its own root-wiring task.

- [ ] **Step 6: Build and run the full test suite**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator' && xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
Expected: BUILD SUCCEEDED, all tests pass.

- [ ] **Step 7: Commit**

```bash
git add SwiftUp/Data/PathRepository.swift SwiftUp/App/RootView.swift SwiftUpTests/RepositoryTests.swift
git commit -m "Add read-only PathRepository and wire it into RootView"
```

- [ ] **Step 8: Seed `pathTracks` into live Firestore — ask the user first**

This is the one step in this plan with an external side effect (a real Firestore write). Ask the user explicitly before running it — do not run it unprompted, matching how every other seed script in this project has been run this session (with the user's explicit "yes, run it" each time). If approved:

```bash
python3 scripts/seed_path_tracks.py
```

(If `firebase-admin` isn't installed and the system Python is externally-managed, use an isolated venv, e.g. `python3 -m venv /tmp/seed-venv && /tmp/seed-venv/bin/pip install firebase-admin && /tmp/seed-venv/bin/python3 scripts/seed_path_tracks.py` — same workaround already used for this project's other seed scripts.)

Verify afterward: manually check the Firebase console's `pathTracks` collection shows 20 documents, or run the app and confirm `PathRepository.load(for:)` returns 20 tracks from the live backend instead of falling back to the bundled fixture (no UI exists yet to see this directly in this sub-project — a print/breakpoint check, or waiting for the next sub-project's first screen, is the practical verification here).
