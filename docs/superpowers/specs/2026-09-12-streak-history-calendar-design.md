# Streak History Calendar — Design

Source design: Claude Design project "Design prioritization inquiry" (`SwiftUp Daily Quiz.dc.html`), turn `t3`/option `3a` ("Profile — rank front page", superseding the older `t2`/`2a`) — the "Sixteen weeks" mark grid below the "Next milestone" section.

## 1. Goal

`ProfileHomeView` (the Record tab's root screen) already renders the milestone cards ("Fifty in a row", "Cycle breaker") the design shows — those are fully implemented. What's missing is the grid below them: a 16-week history of daily-quiz activity, each day marked done / freeze / missed, with a legend and a "Freezes N of 3" counter.

Building this exposes a real backend gap: `StreakCalculator` and `ProfileRepository` today track streak length and freezes-available as running counters only — no record exists of *which calendar day* a freeze covered. Confirmed with the user: freeze usage will be recorded **going forward only**; days before this ships show as `missed` (the honest answer — there is no data to say otherwise), not reconstructed retroactively.

Also confirmed with the user: the grid is **16 columns × 7 rows = 112 real calendar days**, not the mockup's literal 16×5 (80 cells) — the "5 rows" in the Claude Design file is treated as a design-tool slip against the "sixteen weeks" label, not an intentional weekdays-only tracker.

**Out of scope:** milestone cards (already built), any change to `AchievementEngine`/`recentCompletions`/the 31-day fetch it uses, a cross-category "due" indicator, making the grid a full year (explicitly flagged in the design's own "try next" as future work, not this pass).

## 2. Firestore schema

No new collection. `users/{uid}/dailyCompletions/{date}` gains a second possible shape, written only when a freeze is consumed:

```
users/{uid}/dailyCompletions/{date} =
    { correctCount: Int, xpEarned: Int }   // existing shape — a completed day
  | { frozen: true }                        // new — a day forgiven by a streak freeze
```

A given date document is one or the other, never both (a day is either completed or it's the one day a freeze covered — `StreakCalculator`'s gap==2 branch only fires when exactly one day was missed). No `firestore.rules` change — the existing `dailyCompletions/{date}` owner-only rule already covers both shapes.

## 3. `StreakCalculator` — date math and frozen-day reporting

Add a small reusable date-offset helper (extends the file's existing UTC-safe calendar/formatter pattern — reused both internally and by `ProfileRepository`, §4):

```swift
/// `date` shifted by `days` (negative to go backward), in the same UTC calendar `daysBetween` uses
/// — the calendar arithmetic must stay pinned to the timezone the formatter parsed in, or a DST
/// transition can shift the result by a day (see `daysBetween`'s own comment on this).
static func dateOffset(_ days: Int, from date: String) -> String? {
    guard let base = dateFormatter.date(from: date) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = dateFormatter.timeZone
    guard let shifted = calendar.date(byAdding: .day, value: days, to: base) else { return nil }
    return dateFormatter.string(from: shifted)
}
```

`apply(...)` gains a third return value, `frozenDate: String?` — the one date a freeze covered this call, non-nil only on the gap==2-with-a-freeze branch:

```swift
static func apply(
    lastCompletedDate: String?, streakDays: Int, freezesAvailable: Int, today: String
) -> (streakDays: Int, freezesAvailable: Int, frozenDate: String?) {
    guard let lastCompletedDate, let gap = daysBetween(lastCompletedDate, today), gap > 0 else {
        return lastCompletedDate == nil ? (1, freezesAvailable, nil) : (streakDays, freezesAvailable, nil)
    }
    switch gap {
    case 1:
        let result = grow(streakDays: streakDays, freezesAvailable: freezesAvailable)
        return (result.0, result.1, nil)
    case 2 where freezesAvailable > 0:
        let result = grow(streakDays: streakDays, freezesAvailable: freezesAvailable - 1)
        return (result.0, result.1, dateOffset(-1, from: today))
    default:
        return (1, freezesAvailable, nil)
    }
}
```

(`grow` itself is unchanged — still returns the plain `(Int, Int)` pair; only `apply`'s own return type grows.) The frozen date is always `today` minus 1 day: gap==2 means exactly one calendar day sits between the last completion and today, and that day is the one the freeze forgave.

## 4. `ProfileRepository` — recording and fetching frozen/missed history

**`recordCompletion` change** — after computing `streakResult` (now the 3-tuple above), add one more write to the existing batch whenever a freeze was consumed:

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
...
```

Still one atomic commit — this is additive to the existing batch, not a second round trip.

**New `StreakDayState` enum** (own file, `SwiftUp/Models/StreakDayState.swift`, matching the one-small-type-per-file convention already used for `FlashcardRating`):

```swift
enum StreakDayState {
    case done, freeze, missed
}
```

**New stored state + fetch on `ProfileRepository`:**

```swift
private(set) var streakDayRecords: [String: StreakDayState] = [:]   // keyed by "yyyy-MM-dd", only present days

/// The last 112 calendar days as an ordered grid input — oldest first, today last. A day with no
/// entry in `streakDayRecords` (never completed, never frozen) is `.missed`; that includes today
/// itself before it's been completed.
var streakCalendarDays: [StreakDayState] {
    let today = Self.todayString()
    return (0..<112).compactMap { offset -> StreakDayState? in
        guard let date = StreakCalculator.dateOffset(-(111 - offset), from: today) else { return nil }
        return streakDayRecords[date] ?? .missed
    }
}
```

**New fetch**, mirroring `fetchRecentCompletions`'s shape but as a range query instead of a doc-count limit (a count limit would silently pull in days further back than 112 calendar days if there are gaps in the history — wrong for a fixed 112-cell grid):

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

Called alongside the existing `fetchRecentCompletions` call inside `load(for:)` (concurrent, same pattern as the interview-prep repository's `async let` pairs) and stored into `streakDayRecords`. After a successful `recordCompletion` commit, update `streakDayRecords` locally (no re-fetch, matching this method's existing "reflect the result immediately" style): set `streakDayRecords[today] = .done`, and `streakDayRecords[frozenDate] = .freeze` when a freeze was consumed.

## 5. `StreakCalendarGrid` — new view

New file `SwiftUp/DesignSystem/StreakCalendarGrid.swift`, self-contained (grid + legend together, since the legend is meaningless without the grid it explains):

```swift
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
```

Color mapping matches the design file exactly (§ design-intent note: "filled for done, neutral for missed, cyan for a freeze" — this design system's teal accent is `Theme.Colors.accent`).

## 6. `ProfileHomeView` wiring

Added directly after the existing "Next milestone" section (`ProfileHomeView.swift`, after the `ForEach(repo.inReachAchievements)` block), matching the design's own section order:

```swift
HStack {
    EyebrowLabel("Sixteen weeks")
    Spacer()
    EyebrowLabel("Freezes \(repo.profile.freezesAvailable) of \(repo.profile.freezesTotal)")
}
.padding(.top, 28)

StreakCalendarGrid(days: repo.streakCalendarDays)
    .padding(.top, 12)
```

No new environment objects needed — `repo` (`ProfileRepository`) is already injected on this screen.

## 7. Error handling

`fetchStreakDayRecords` failure: caught by `load(for:)`'s existing outer `do`/`catch` (non-blocking, same as every other field on this repository) — `streakDayRecords` stays whatever it was (empty on first load, stale-but-present on a later transient failure), so the grid renders as it did most recently rather than crashing or flashing empty.

`recordCompletion`'s frozen-day write failure: covered by the existing outer `catch` for that method (non-blocking) — worst case that one day's frozen marker is lost, same "next completion recomputes from whatever's stored" risk the method's own doc comment already accepts for every other field it writes.

## 8. Testing

- `StreakCalculator.dateOffset(_:from:)`: forward and backward offsets, and an offset crossing a month/year boundary.
- `StreakCalculator.apply(...)`'s new `frozenDate` return value: `nil` on the gap==1 (grow) and gap>2/reset branches; equal to `today` minus 1 day on the gap==2-with-freeze branch. Existing `StreakCalculatorTests.swift` cases need their call sites updated for the 3-tuple return (mechanical — each existing assertion on `.streakDays`/`.freezesAvailable` is unaffected, they just also get a `.frozenDate` to optionally assert `nil` on).
- `ProfileRepository.streakCalendarDays`: given a `streakDayRecords` dictionary with a few scattered `.done`/`.freeze` entries and gaps, produces exactly 112 entries in oldest-to-newest order with gaps as `.missed`. This is pure/testable without Firestore since `streakDayRecords` is just a stored dictionary — a test can construct a `ProfileRepository` via `preview()` and can't directly set `private(set) var streakDayRecords`, so this needs either a small `internal`/test-visible seam or is verified indirectly; flagged as an open decision (§9).
- Firestore reads/writes themselves aren't unit-testable in this project (no emulator, same limitation as every other repository) — verified by manual run-through: complete today's quiz, confirm `dailyCompletions/{today}` gets `correctCount`; skip exactly one day then complete the next, confirm `dailyCompletions/{skippedDate}` gets `{frozen: true}` and the grid shows that cell as freeze-colored.

## 9. Open implementation decisions (flagged, not blocking)

- How `streakCalendarDays`' pure logic gets unit-tested given `streakDayRecords` is `private(set)`: either add an `internal` test-only initializer/setter, or test the date-window math as a free function taking the dictionary as a parameter (e.g. factor the body of `streakCalendarDays` into a static `ProfileRepository.buildCalendarDays(from: [String: StreakDayState], today: String) -> [StreakDayState]` that the computed property calls) — the latter is cleaner and costs nothing at the call site, recommended at implementation time.
- Exact spacing/sizing constants in `StreakCalendarGrid` (cell height 11pt, gaps 3pt, per the design file) — implementation-time detail, not a design decision that changes behavior.
