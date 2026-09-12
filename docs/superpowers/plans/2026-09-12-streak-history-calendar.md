# Streak History Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the "Sixteen weeks" streak-history grid (done/freeze/missed per day, legend, freeze counter) to `ProfileHomeView`, backed by real per-day Firestore data — including recording, for the first time, which specific calendar day a streak freeze covered.

**Architecture:** `StreakCalculator` gains a reusable UTC-safe date-offset helper and reports the one date a freeze covered (`frozenDate`) alongside its existing streak/freeze counters. `ProfileRepository.recordCompletion` writes that date to `dailyCompletions/{frozenDate} = {frozen: true}` in its existing batch commit. A new range-queried fetch (`fetchStreakDayRecords`) loads the last 112 days of `dailyCompletions` docs into a `[String: StreakDayState]` dictionary, and a pure static helper (`buildCalendarDays`) turns that into the ordered 112-entry array a new `StreakCalendarGrid` view renders.

**Tech Stack:** Swift 6 / SwiftUI, Firebase Firestore, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-12-streak-history-calendar-design.md`

## Global Constraints

- Firestore schema: `users/{uid}/dailyCompletions/{date}` now has two mutually-exclusive shapes — the existing `{correctCount: Int, xpEarned: Int}` (a completed day) or the new `{frozen: true}` (a day a streak freeze covered). No `firestore.rules` change — the existing owner-only `dailyCompletions/{date}` rule already covers both (spec §2).
- Grid is **16 columns × 7 rows = 112 real calendar days**, oldest first, today last (spec §1/§4).
- Freeze history is recorded **going forward only** — days before this ships show `.missed`, never reconstructed retroactively (spec §1).
- No changes to `AchievementEngine`, `recentCompletions`, or its 31-day fetch — the new 112-day fetch is a separate method (spec §2/§4).
- Color mapping: done → `Theme.Colors.text`, freeze → `Theme.Colors.accent`, missed → `Theme.Colors.neutral200` (spec §5).
- `StreakCalculator.dateOffset(_:from:)` reuses the file's existing UTC-pinned `Calendar`/`DateFormatter` — the same DST-safety reasoning as the existing `daysBetween` (spec §3).
- All existing `StreakCalculatorTests.swift` cases access the result by named member (`.streakDays`, `.freezesAvailable`) — adding a third named tuple member (`frozenDate`) is source-compatible and requires **no changes** to any existing test.

---

## Task 1: `StreakCalculator` — date-offset helper and frozen-date reporting

**Files:**
- Modify: `SwiftUp/Data/StreakCalculator.swift`
- Modify: `SwiftUpTests/StreakCalculatorTests.swift`

**Interfaces:**
- Produces: `StreakCalculator.dateOffset(_ days: Int, from date: String) -> String?` (static), `StreakCalculator.apply(...) -> (streakDays: Int, freezesAvailable: Int, frozenDate: String?)` (return type gains a third member; existing named-member call sites elsewhere in the app are unaffected).

- [ ] **Step 1: Write the failing tests**

Add to `SwiftUpTests/StreakCalculatorTests.swift`, after `dayGapArithmeticIgnoresTheDeviceTimeZone`:

```swift
    // MARK: - dateOffset

    @Test func dateOffsetMovesBackwardAndForward() {
        #expect(StreakCalculator.dateOffset(-1, from: "2026-01-10") == "2026-01-09")
        #expect(StreakCalculator.dateOffset(1, from: "2026-01-10") == "2026-01-11")
        #expect(StreakCalculator.dateOffset(0, from: "2026-01-10") == "2026-01-10")
    }

    @Test func dateOffsetCrossesMonthAndYearBoundaries() {
        #expect(StreakCalculator.dateOffset(-1, from: "2026-01-01") == "2025-12-31")
        #expect(StreakCalculator.dateOffset(-111, from: "2026-01-01") == "2025-09-12")
    }

    // MARK: - frozenDate

    @Test func frozenDateIsNilWhenStreakJustGrows() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 0, today: "2026-01-11")
        #expect(result.frozenDate == nil)
    }

    @Test func frozenDateIsTheDayBeforeTodayWhenAFreezeIsConsumed() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 1, today: "2026-01-12")
        #expect(result.streakDays == 6)
        #expect(result.freezesAvailable == 0)
        #expect(result.frozenDate == "2026-01-11")
    }

    @Test func frozenDateIsNilWhenTheGapIsTooWideToForgive() {
        let result = StreakCalculator.apply(lastCompletedDate: "2026-01-10", streakDays: 5, freezesAvailable: 1, today: "2026-01-14")
        #expect(result.frozenDate == nil)
    }

    @Test func frozenDateIsNilOnFirstEverCompletion() {
        let result = StreakCalculator.apply(lastCompletedDate: nil, streakDays: 0, freezesAvailable: 0, today: "2026-01-10")
        #expect(result.frozenDate == nil)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -only-testing:SwiftUpTests/StreakCalculatorTests 2>&1 | tail -60
```
Expected: build error — `dateOffset` doesn't exist yet, and `.frozenDate` isn't a member of `apply`'s current return type.

(If the destination's OS version differs on the machine this runs on, check `xcrun simctl list devices available` and substitute the closest match to `iPhone 16` — this project's test destination has needed adjustment before when the simulator runtime set changed.)

- [ ] **Step 3: Implement `dateOffset` and extend `apply`**

Replace the whole file's `apply`/`grow` section (everything from `static func apply` through the end of `grow`) with:

```swift
    /// `date` shifted by `days` (negative to go backward), in the same UTC calendar `daysBetween`
    /// uses — the arithmetic must stay pinned to the timezone the formatter parsed in, or a DST
    /// transition can shift the result by a day (see `daysBetween`'s own comment on this).
    static func dateOffset(_ days: Int, from date: String) -> String? {
        guard let base = dateFormatter.date(from: date) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = dateFormatter.timeZone
        guard let shifted = calendar.date(byAdding: .day, value: days, to: base) else { return nil }
        return dateFormatter.string(from: shifted)
    }

    static func apply(
        lastCompletedDate: String?, streakDays: Int, freezesAvailable: Int, today: String
    ) -> (streakDays: Int, freezesAvailable: Int, frozenDate: String?) {
        guard let lastCompletedDate, let gap = daysBetween(lastCompletedDate, today), gap > 0 else {
            // No prior completion: today starts streak day 1. Same-day or unparseable/negative gap: no-op.
            return lastCompletedDate == nil ? (1, freezesAvailable, nil) : (streakDays, freezesAvailable, nil)
        }
        switch gap {
        case 1:
            let result = grow(streakDays: streakDays, freezesAvailable: freezesAvailable)
            return (result.0, result.1, nil)
        case 2 where freezesAvailable > 0:
            let result = grow(streakDays: streakDays, freezesAvailable: freezesAvailable - 1)
            // The one day the freeze forgave — a 2-day gap means exactly one calendar day sits
            // between the last completion and today.
            return (result.0, result.1, dateOffset(-1, from: today))
        default:
            return (1, freezesAvailable, nil)
        }
    }

    private static func grow(streakDays: Int, freezesAvailable: Int) -> (Int, Int) {
        let newStreak = streakDays + 1
        let freezes = newStreak % 7 == 0 ? min(freezesAvailable + 1, 3) : freezesAvailable
        return (newStreak, freezes)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -only-testing:SwiftUpTests/StreakCalculatorTests 2>&1 | tail -40
```
Expected: `** TEST SUCCEEDED **`, all existing cases still pass unmodified (they access `.streakDays`/`.freezesAvailable` by name).

- [ ] **Step 5: Build the full app target**

`StreakCalculator.apply`'s only other caller is `ProfileRepository.recordCompletion`, which destructures the result via named members (`streakResult.streakDays`, `streakResult.freezesAvailable`) — adding a third tuple member doesn't break that call site, so the full app should still build without any other file changing.

```bash
xcodebuild -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add SwiftUp/Data/StreakCalculator.swift SwiftUpTests/StreakCalculatorTests.swift
git commit -m "$(cat <<'EOF'
Report which day a streak freeze covered

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013qjjTWqmcJt7Z6N6odvUkp
EOF
)"
```

---

## Task 2: `StreakDayState`, `ProfileRepository`'s history fetch, and the frozen-day write

**Files:**
- Create: `SwiftUp/Models/StreakDayState.swift`
- Modify: `SwiftUp/Data/ProfileRepository.swift`
- Modify: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Consumes: `StreakCalculator.dateOffset(_:from:)`, `StreakCalculator.apply(...).frozenDate` (Task 1).
- Produces: `enum StreakDayState { case done, freeze, missed }`, `ProfileRepository.streakDayRecords: [String: StreakDayState]`, `ProfileRepository.streakCalendarDays: [StreakDayState]` (112 entries), `ProfileRepository.buildCalendarDays(from:today:) -> [StreakDayState]` (static, pure, unit-testable).

- [ ] **Step 1: Create `StreakDayState.swift`**

```swift
import Foundation

enum StreakDayState {
    case done, freeze, missed
}
```

- [ ] **Step 2: Write the failing test for the pure calendar-building logic**

Add to `SwiftUpTests/RepositoryTests.swift`, after `leaderboardRepositoryPreviewLoadsEntriesSortedByRank`:

```swift
    @MainActor
    @Test func profileRepositoryBuildsCalendarDaysOldestFirstWithGapsAsMissed() {
        let records: [String: StreakDayState] = [
            "2026-01-08": .done,
            "2026-01-09": .freeze,
            // 2026-01-10 has no entry — must read as .missed
        ]
        let days = ProfileRepository.buildCalendarDays(from: records, today: "2026-01-10")
        #expect(days.count == 112)
        #expect(days[109] == .done)   // 2026-01-08: 2 days before today, index 111-2
        #expect(days[110] == .freeze) // 2026-01-09: 1 day before today
        #expect(days[111] == .missed) // 2026-01-10: today, not yet completed
        #expect(days[0] == .missed)   // 111 days before today: no record, absent, .missed
    }
```

- [ ] **Step 3: Run test to verify it fails**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -only-testing:SwiftUpTests/RepositoryTests 2>&1 | tail -40
```
Expected: build error — `StreakDayState`/`ProfileRepository.buildCalendarDays` don't exist yet. (`StreakDayState.swift` from Step 1 does exist by this point, so only `buildCalendarDays` is missing — that's fine, this step confirms the *test* fails for the right reason.)

- [ ] **Step 4: Add the stored property, pure helper, computed property, and fetch to `ProfileRepository`**

Add a new stored property next to the existing ones:
```swift
    private(set) var streakDayRecords: [String: StreakDayState] = [:]
```

Add near the bottom of the class, alongside `earnedAchievements`/`inReachAchievements`/`lockedAchievements`:
```swift
    /// The last 112 calendar days as an ordered grid input — oldest first, today last. Factored out
    /// as a static, pure function (rather than inline in a computed property reading `self`) so it's
    /// directly unit-testable without touching Firestore or this class's `private(set)` state.
    static func buildCalendarDays(from records: [String: StreakDayState], today: String) -> [StreakDayState] {
        (0..<112).compactMap { offset -> StreakDayState? in
            guard let date = StreakCalculator.dateOffset(-(111 - offset), from: today) else { return nil }
            return records[date] ?? .missed
        }
    }

    var streakCalendarDays: [StreakDayState] {
        Self.buildCalendarDays(from: streakDayRecords, today: Self.todayString())
    }
```

Add the new fetch near `fetchRecentCompletions`:
```swift
    private static func fetchStreakDayRecords(uid: String) async throws -> [String: StreakDayState] {
        let today = todayString()
        guard let startDate = StreakCalculator.dateOffset(-111, from: today) else { return [:] }
        let snapshot = try await Firestore.firestore()
            .collection("users").document(uid).collection("dailyCompletions")
            .whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: startDate)
            .getDocuments()
        return snapshot.documents.reduce(into: [:]) { result, doc in
            if doc.get("correctCount") != nil {
                result[doc.documentID] = .done
            } else if doc.get("frozen") as? Bool == true {
                result[doc.documentID] = .freeze
            }
        }
    }
```

- [ ] **Step 5: Wire the fetch into `load(for:)`**

Replace:
```swift
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        let userRef = Firestore.firestore().collection("users").document(uid)
        do {
            let snapshot = try await userRef.getDocument()
            let recentCompletions = try await Self.fetchRecentCompletions(uid: uid)
            apply(snapshot: snapshot, recentCompletions: recentCompletions)
        } catch {
            // Intentionally left as-is — see doc comment above.
        }
    }
```
with:
```swift
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        let userRef = Firestore.firestore().collection("users").document(uid)
        do {
            async let snapshot = userRef.getDocument()
            async let recentCompletions = Self.fetchRecentCompletions(uid: uid)
            async let streakDayRecords = Self.fetchStreakDayRecords(uid: uid)
            let (resolvedSnapshot, resolvedRecent, resolvedStreakDays) = try await (snapshot, recentCompletions, streakDayRecords)
            self.streakDayRecords = resolvedStreakDays
            apply(snapshot: resolvedSnapshot, recentCompletions: resolvedRecent)
        } catch {
            // Intentionally left as-is — see doc comment above.
        }
    }
```

- [ ] **Step 6: Write the frozen-day marker in `recordCompletion`, and reflect it locally**

The `let streakResult = StreakCalculator.apply(...)` call site itself needs no edit — Task 1 changed `apply`'s return type, and this call already reads the result by named member, so it keeps compiling and now also has `streakResult.frozenDate` available. Two edits follow.

Replace:
```swift
            let batch = Firestore.firestore().batch()
            batch.setData(userUpdates, forDocument: userRef, merge: true)
            let dayRef = userRef.collection("dailyCompletions").document(today)
            batch.setData(["correctCount": session.correctCount, "xpEarned": session.totalXPEarned], forDocument: dayRef)
            let leaderboardRef = Firestore.firestore().collection("leaderboardEntries").document(uid)
```
with:
```swift
            let batch = Firestore.firestore().batch()
            batch.setData(userUpdates, forDocument: userRef, merge: true)
            let dayRef = userRef.collection("dailyCompletions").document(today)
            batch.setData(["correctCount": session.correctCount, "xpEarned": session.totalXPEarned], forDocument: dayRef)
            if let frozenDate = streakResult.frozenDate {
                let frozenRef = userRef.collection("dailyCompletions").document(frozenDate)
                batch.setData(["frozen": true], forDocument: frozenRef)
            }
            let leaderboardRef = Firestore.firestore().collection("leaderboardEntries").document(uid)
```

Replace:
```swift
            let freezesAvailable = streakResult.freezesAvailable
            profile = Self.buildProfile(
                displayName: displayName,
                createdAt: snapshot.get("createdAt") as? Timestamp,
                freezesAvailable: freezesAvailable, stats: stats, level: level
            )
            topics = topicStats.map { TopicAccuracy(name: $0.key, accuracyPercent: Self.accuracy($0.value)) }.sorted { $0.name < $1.name }
            achievements = AchievementEngine.evaluate(catalog: catalog, stats: stats, earnedAt: earnedAt)
        } catch {
            // Non-blocking — see doc comment above.
        }
    }
```
with:
```swift
            let freezesAvailable = streakResult.freezesAvailable
            profile = Self.buildProfile(
                displayName: displayName,
                createdAt: snapshot.get("createdAt") as? Timestamp,
                freezesAvailable: freezesAvailable, stats: stats, level: level
            )
            topics = topicStats.map { TopicAccuracy(name: $0.key, accuracyPercent: Self.accuracy($0.value)) }.sorted { $0.name < $1.name }
            achievements = AchievementEngine.evaluate(catalog: catalog, stats: stats, earnedAt: earnedAt)
            streakDayRecords[today] = .done
            if let frozenDate = streakResult.frozenDate {
                streakDayRecords[frozenDate] = .freeze
            }
        } catch {
            // Non-blocking — see doc comment above.
        }
    }
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -only-testing:SwiftUpTests/RepositoryTests 2>&1 | tail -40
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Run `xcodegen generate` (new model file added) and build the full app target**

```bash
xcodegen generate
xcodebuild -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add SwiftUp/Models/StreakDayState.swift SwiftUp/Data/ProfileRepository.swift SwiftUpTests/RepositoryTests.swift
git commit -m "$(cat <<'EOF'
Fetch and record per-day streak history for the calendar grid

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013qjjTWqmcJt7Z6N6odvUkp
EOF
)"
```

---

## Task 3: `StreakCalendarGrid` view and `ProfileHomeView` wiring

**Files:**
- Create: `SwiftUp/DesignSystem/StreakCalendarGrid.swift`
- Modify: `SwiftUp/Features/Profile/ProfileHomeView.swift`

**Interfaces:**
- Consumes: `StreakDayState` (Task 2), `ProfileRepository.streakCalendarDays` (Task 2), `Theme.Colors.text`/`.accent`/`.neutral200` (`SwiftUp/DesignSystem/Theme.swift`, unchanged), `EyebrowLabel` (`SwiftUp/DesignSystem/Atoms.swift`, unchanged).
- Produces: `StreakCalendarGrid(days: [StreakDayState])`.

- [ ] **Step 1: Create `StreakCalendarGrid.swift`**

```swift
import SwiftUI

struct StreakCalendarGrid: View {
    /// Exactly 112 entries, oldest first, today last — `ProfileRepository.streakCalendarDays`.
    let days: [StreakDayState]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<16, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { day in
                            let index = week * 7 + day
                            Rectangle()
                                .fill(index < days.count ? color(for: days[index]) : Theme.Colors.neutral200)
                                .frame(height: 11)
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                legendItem("done", color: Theme.Colors.text)
                legendItem("freeze", color: Theme.Colors.accent)
                legendItem("missed", color: Theme.Colors.neutral200)
            }
        }
    }

    private func color(for state: StreakDayState) -> Color {
        switch state {
        case .done: Theme.Colors.text
        case .freeze: Theme.Colors.accent
        case .missed: Theme.Colors.neutral200
        }
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            EyebrowLabel(label)
        }
    }
}

#Preview {
    StreakCalendarGrid(days: (0..<112).map { i in
        if i % 23 == 0 { .freeze } else if i % 5 == 0 { .missed } else { .done }
    })
    .padding()
    .background(Theme.Colors.bg)
}
```

- [ ] **Step 2: Wire it into `ProfileHomeView`**

In `SwiftUp/Features/Profile/ProfileHomeView.swift`, replace:
```swift
                VStack(spacing: 14) {
                    ForEach(repo.inReachAchievements) { a in
                        milestoneRow(a)
                    }
                }
                .padding(.top, 12)

                Spacer(minLength: 20)
```
with:
```swift
                VStack(spacing: 14) {
                    ForEach(repo.inReachAchievements) { a in
                        milestoneRow(a)
                    }
                }
                .padding(.top, 12)

                HStack {
                    EyebrowLabel("Sixteen weeks")
                    Spacer()
                    EyebrowLabel("Freezes \(repo.profile.freezesAvailable) of \(repo.profile.freezesTotal)")
                }
                .padding(.top, 28)

                StreakCalendarGrid(days: repo.streakCalendarDays)
                    .padding(.top, 12)

                Spacer(minLength: 20)
```

- [ ] **Step 3: Run `xcodegen generate` and build the full app target**

```bash
xcodegen generate
xcodebuild -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full test suite**

```bash
xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' 2>&1 | tail -40
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/DesignSystem/StreakCalendarGrid.swift SwiftUp/Features/Profile/ProfileHomeView.swift
git commit -m "$(cat <<'EOF'
Add the sixteen-week streak history grid to the profile screen

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013qjjTWqmcJt7Z6N6odvUkp
EOF
)"
```

- [ ] **Step 6: Manual verification (no code, no commit)**

Firestore reads/writes for `dailyCompletions` aren't unit-testable in this project (no emulator). Verify by hand on a signed-in device/simulator:
1. Complete today's quiz; confirm `dailyCompletions/{today}` gets `{correctCount, xpEarned}` and the grid's last cell turns "done"-colored on next load.
2. Force a one-day gap (skip a day, then complete the next day with a freeze available); confirm `dailyCompletions/{skippedDate}` gets `{frozen: true}` and that cell renders in the freeze color.
3. Confirm a day with no completion and no freeze renders as "missed"-colored, including today itself before it's completed.
