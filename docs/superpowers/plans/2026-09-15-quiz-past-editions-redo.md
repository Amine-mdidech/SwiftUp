# Daily Quiz — Past Editions Redo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After finishing today's daily quiz, show a new "editions" screen with the user's streak, today's XP, and a tappable row of the last 7 calendar days, letting them redo any open (not-yet-completed) day's quiz purely for practice — zero effect on XP, accuracy, or streak — behind a swappable (currently no-op) ad-presentation seam.

**Architecture:** Two existing repositories (`QuestionRepository`, `ProfileRepository`) each gain one small, pure/Firestore-backed addition (an exposed `effectiveLevel` + a past-quiz fetch; a 7-day window view over already-loaded streak data). `QuizSession` gains an additive `isPractice` flag it never reads itself — the "zero impact" guarantee is structural: a practice run simply never reaches `ProfileRepository.recordCompletion` or `QuestionRepository.recordAnswered`, because `TodayFlowView`'s practice code path (`advancePractice`) doesn't call them, unlike the real path (`advance`/`recordCompletion`). A new `QuizEditionsView` renders the hub screen and a new `RewardedAdPresenting` protocol (with a `NoOpAdPresenter` default) gates starting a replay, ready to swap for a real ad SDK later without touching the redo flow itself.

**Tech Stack:** SwiftUI (iOS 17+), `@Observable` (Observation framework), Firebase Firestore, Swift Testing (`import Testing`, `@Test`, `#expect`), XcodeGen (`xcodegen generate` after adding/removing files).

**Spec:** `docs/superpowers/specs/2026-09-15-quiz-past-editions-redo-design.md`

## Global Constraints

- **Zero stat impact for a practice redo:** no XP, no topic-accuracy credit, no streak change. Achieved structurally — the practice code path never calls `ProfileRepository.recordCompletion` or `QuestionRepository.recordAnswered` — not via conditionals inside those methods.
- **No "longest streak ever" tracking is added.** The editions screen shows only the current streak count (`profileRepo.profile.streakDays`) and today's XP.
- **No new Firestore fields, collections, or writes** of any kind for this feature. All reads reuse `dailyQuizzes/{date}` (already exists) and `streakDayRecords`/`StreakDayState` (already loaded by `ProfileRepository.load`).
- **The ad seam is a swappable protocol, not an ad integration.** `RewardedAdPresenting`/`NoOpAdPresenter` are the entire scope here; no ad SDK is added.
- Every `xcodebuild`/`xcodegen` command must run in the **foreground** — never background a build or test run.
- Tests run on `-destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'` (the bare `name=iPhone 16` destination is ambiguous on this machine — always pin `OS=18.6`). A full-app build (no tests) instead uses `-destination 'generic/platform=iOS Simulator'`.
- After adding or removing any file, run `xcodegen generate` from the repo root before building.
- Two pre-existing **untracked** files, `SwiftUp/App/SplashView.swift` and `SwiftUp/Assets.xcassets/`, belong to the user's own separate in-progress work — never commit them, and copy them into any new worktree so the baseline builds.

---

## Task 1: `DailyEdition` weekday helpers, `QuestionRepository.effectiveLevel`/`fetchPastQuiz`, `ProfileRepository.lastSevenDays`

**Files:**
- Modify: `SwiftUp/Data/DailyEdition.swift`
- Modify: `SwiftUp/Data/QuestionRepository.swift`
- Modify: `SwiftUp/Data/ProfileRepository.swift`
- Test: `SwiftUpTests/DailyEditionTests.swift`
- Test: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Produces (consumed by Task 3's `QuizEditionsView`): `DailyEdition.weekdayName(for dateKey: String, timeZone: TimeZone = .current) -> String` (full name, e.g. `"Friday"`), `DailyEdition.shortWeekdayName(for dateKey: String, timeZone: TimeZone = .current) -> String` (e.g. `"Fri"`).
- Produces (consumed by Task 2's `TodayFlowView.startReplay`): `QuestionRepository.effectiveLevel: SkillLevel` (already-`private(set) var`, defaults `.junior`), `QuestionRepository.fetchPastQuiz(for dateKey: String) async -> DailyQuizDocument?`.
- Produces (consumed by Task 3's `QuizEditionsView`): `ProfileRepository.lastSevenDays: [(date: String, state: StreakDayState)]` — exactly 7 entries, oldest first, today last.
- Consumes: `StreakCalculator.dateOffset(_:from:)` (existing), `StreakDayState` (existing enum in `SwiftUp/Models/StreakDayState.swift`, cases `.done`/`.freeze`/`.missed`).

- [ ] **Step 1: Write the failing tests for the `DailyEdition` weekday helpers**

Add to `SwiftUpTests/DailyEditionTests.swift` (inside `struct DailyEditionTests`, alongside the existing tests):

```swift
    @Test func weekdayNameReturnsFullWeekday() throws {
        #expect(DailyEdition.weekdayName(for: "2026-09-07", timeZone: Self.utc) == "Monday")
        #expect(DailyEdition.weekdayName(for: "2026-09-10", timeZone: Self.utc) == "Thursday")
    }

    @Test func shortWeekdayNameReturnsThreeLetterAbbreviation() throws {
        #expect(DailyEdition.shortWeekdayName(for: "2026-09-07", timeZone: Self.utc) == "Mon")
        #expect(DailyEdition.shortWeekdayName(for: "2026-09-10", timeZone: Self.utc) == "Thu")
    }

    @Test func weekdayNameReturnsEmptyStringForAnUnparseableKey() {
        #expect(DailyEdition.weekdayName(for: "not-a-date", timeZone: Self.utc) == "")
        #expect(DailyEdition.shortWeekdayName(for: "not-a-date", timeZone: Self.utc) == "")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/DailyEditionTests`
Expected: FAIL — `weekdayName`/`shortWeekdayName` are not members of `DailyEdition`.

- [ ] **Step 3: Implement the weekday helpers**

In `SwiftUp/Data/DailyEdition.swift`, add inside `enum DailyEdition` (after the existing `todayKey` method):

```swift
    /// Parses a `yyyy-MM-dd` calendar-day key (the same convention `todayKey` produces) back into
    /// a `Date` for display formatting. `nil` for a malformed key.
    private static func date(from dateKey: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateKey)
    }

    /// Full weekday name ("Friday") for a `yyyy-MM-dd` key — e.g. the past-editions redo button's
    /// "Sit Friday's" copy. Empty string for a malformed key (never reachable from real streak-day
    /// data, but keeps this a total function for callers).
    static func weekdayName(for dateKey: String, timeZone: TimeZone = .current) -> String {
        guard let parsed = date(from: dateKey, timeZone: timeZone) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: parsed)
    }

    /// Three-letter weekday abbreviation ("Fri") for a `yyyy-MM-dd` key — the compact day-block
    /// labels on the past-editions redo row.
    static func shortWeekdayName(for dateKey: String, timeZone: TimeZone = .current) -> String {
        guard let parsed = date(from: dateKey, timeZone: timeZone) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: parsed)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/DailyEditionTests`
Expected: PASS

- [ ] **Step 5: Write the failing test for `ProfileRepository.buildLastSevenDays`**

Add to `SwiftUpTests/RepositoryTests.swift` (inside `struct RepositoryTests`, alongside the existing `@MainActor` calendar-days tests):

```swift
    @MainActor
    @Test func profileRepositoryBuildsLastSevenDaysOldestFirstTodayLastWithGapsAsMissed() {
        let records: [String: StreakDayState] = [
            "2026-01-08": .done,
            "2026-01-09": .freeze,
            // 2026-01-10 (today) intentionally has no entry — a fresh completion never lands before
            // this screen renders (see spec §11).
        ]
        let days = ProfileRepository.buildLastSevenDays(from: records, today: "2026-01-10")
        #expect(days.count == 7)
        #expect(days.map(\.date) == ["2026-01-04", "2026-01-05", "2026-01-06", "2026-01-07", "2026-01-08", "2026-01-09", "2026-01-10"])
        #expect(days[4].state == .done)   // 2026-01-08
        #expect(days[5].state == .freeze) // 2026-01-09
        #expect(days[6].state == .missed) // 2026-01-10, today, no record
        #expect(days[0].state == .missed) // 2026-01-04, no record
    }
```

This mirrors the existing `profileRepositoryBuildsCalendarDays*` tests exactly: a static, pure function taking `records`/`today` as plain arguments, so the 7-day window logic is testable without touching Firestore or the device clock.

- [ ] **Step 6: Run the test to verify it fails**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: FAIL — `ProfileRepository.buildLastSevenDays` doesn't exist yet.

- [ ] **Step 7: Refactor `buildCalendarDays`'s date-listing into a shared helper, add `buildLastSevenDays` and `lastSevenDays`**

In `SwiftUp/Data/ProfileRepository.swift`, replace the existing `buildCalendarDays` static method (currently around line 321-326):

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
```

with:

```swift
    /// `count` calendar-day keys ending at `today`, oldest first. Shared by `buildCalendarDays`
    /// (112-day grid) and `buildLastSevenDays` (7-day redo picker) so the offset arithmetic lives in
    /// one place.
    private static func recentDates(before today: String, count: Int) -> [String] {
        (0..<count).compactMap { offset in StreakCalculator.dateOffset(-(count - 1 - offset), from: today) }
    }

    /// The last 112 calendar days as an ordered grid input — oldest first, today last. Factored out
    /// as a static, pure function (rather than inline in a computed property reading `self`) so it's
    /// directly unit-testable without touching Firestore or this class's `private(set)` state.
    static func buildCalendarDays(from records: [String: StreakDayState], today: String) -> [StreakDayState] {
        recentDates(before: today, count: 112).map { records[$0] ?? .missed }
    }

    /// Today + the 6 days before it, oldest first, today last, paired with their state — the pure
    /// core of `lastSevenDays` below (mirrors `buildCalendarDays`), directly unit-testable without
    /// touching Firestore or the device clock.
    static func buildLastSevenDays(from records: [String: StreakDayState], today: String) -> [(date: String, state: StreakDayState)] {
        recentDates(before: today, count: 7).map { ($0, records[$0] ?? .missed) }
    }
```

Then add, directly after the existing `streakCalendarDays` computed property (end of the class, before the closing brace):

```swift
    /// Today + the 6 days before it, oldest first, today last — for the post-quiz "redo an earlier
    /// day" picker. Unlike `streakCalendarDays`, callers need the date string itself (to know which
    /// day a tap means), not just its state.
    var lastSevenDays: [(date: String, state: StreakDayState)] {
        Self.buildLastSevenDays(from: streakDayRecords, today: Self.todayString())
    }
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: PASS — including the pre-existing `profileRepositoryBuildsCalendarDays*` tests (confirms the `recentDates` refactor didn't change `buildCalendarDays`'s behavior).

- [ ] **Step 9: Add `QuestionRepository.effectiveLevel` storage and `fetchPastQuiz`**

In `SwiftUp/Data/QuestionRepository.swift`, add the stored property (after the existing `levelOverride` declaration near the top of the class):

```swift
    private(set) var effectiveLevel: SkillLevel = .junior
```

Then, inside `load(for uid:)`, immediately after the existing two lines that set `todayQuestions`/`editionNumber` (find `todayQuestions = daily.questions(for: effectiveLevel)` / `editionNumber = daily.edition`), add the one new line:

```swift
        todayQuestions = daily.questions(for: effectiveLevel)
        editionNumber = daily.edition
        self.effectiveLevel = effectiveLevel   // NEW — the only line added to load(for:)
```

Then add the new method, after `fetchDailyQuiz`:

```swift
    /// A past date's shared daily quiz, for replay/practice — same document shape as today's, just a
    /// different `dailyQuizzes/{date}` key. `nil` if that date was never seeded (predates the app, or
    /// fell outside the seed script's rolling window) — the caller treats this as "nothing to redo."
    func fetchPastQuiz(for dateKey: String) async -> DailyQuizDocument? {
        try? await Firestore.firestore()
            .collection("dailyQuizzes").document(dateKey)
            .getDocument(as: DailyQuizDocument.self)
    }
```

- [ ] **Step 10: Build to verify `QuestionRepository` and `ProfileRepository` compile**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED. `fetchPastQuiz` and `effectiveLevel` touch Firestore/live state and aren't further unit-tested here — same limitation as every other repository method in this project (no emulator).

- [ ] **Step 11: Commit**

```bash
git add SwiftUp/Data/DailyEdition.swift SwiftUp/Data/QuestionRepository.swift SwiftUp/Data/ProfileRepository.swift SwiftUpTests/DailyEditionTests.swift SwiftUpTests/RepositoryTests.swift
git commit -m "Add DailyEdition weekday helpers, QuestionRepository.fetchPastQuiz, ProfileRepository.lastSevenDays"
```

---

## Task 2: `QuizSession.isPractice` flag + `RewardedAdPresenting` ad seam

**Files:**
- Modify: `SwiftUp/Features/DailyQuiz/QuizSession.swift`
- Create: `SwiftUp/Features/DailyQuiz/RewardedAdPresenting.swift`
- Test: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Consumes: nothing new from Task 1.
- Produces (consumed by Task 3): `QuizSession.init(questions: [Question], isPractice: Bool = false)`, `QuizSession.isPractice: Bool`; `protocol RewardedAdPresenting { func presentAd(completion: @escaping (Bool) -> Void) }`, `struct NoOpAdPresenter: RewardedAdPresenting`.

- [ ] **Step 1: Write the failing test for `isPractice`**

Add to `SwiftUpTests/RepositoryTests.swift` (inside `struct RepositoryTests`):

```swift
    @Test func quizSessionDefaultsToNotPracticeAndStoresExplicitFlag() {
        let question = Question(
            id: "q1", topic: "Swift", level: .junior, format: .multipleChoice, prompt: "?",
            codeSnippet: nil, options: [QuestionOption(id: "A", text: "a")],
            correctOptionID: "A", explanation: "e", xp: 10
        )
        let real = QuizSession(questions: [question])
        #expect(real.isPractice == false)

        let practice = QuizSession(questions: [question], isPractice: true)
        #expect(practice.isPractice == true)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: FAIL — `QuizSession.init(questions:isPractice:)` doesn't exist yet (only `init(questions:)` does).

- [ ] **Step 3: Add the `isPractice` flag**

In `SwiftUp/Features/DailyQuiz/QuizSession.swift`, replace:

```swift
    let questions: [Question]
    private(set) var currentIndex: Int = 0
    private var answers: [String: String] = [:]
    private let startedAt = Date()
    private var finishedAt: Date?

    init(questions: [Question]) {
        self.questions = questions
    }
```

with:

```swift
    let questions: [Question]
    /// `true` for a redo of a past day started from `QuizEditionsView`. This flag is never read
    /// inside `QuizSession` itself — "zero stat impact" for a practice redo is structural:
    /// `TodayFlowView.advancePractice` (the only caller that ever advances a practice session)
    /// simply never calls `ProfileRepository.recordCompletion` or `QuestionRepository.recordAnswered`,
    /// unlike `advance()` (the real-quiz path). The flag exists so call sites and future features can
    /// tell which kind of session they're holding without threading a separate parameter everywhere.
    let isPractice: Bool
    private(set) var currentIndex: Int = 0
    private var answers: [String: String] = [:]
    private let startedAt = Date()
    private var finishedAt: Date?

    init(questions: [Question], isPractice: Bool = false) {
        self.questions = questions
        self.isPractice = isPractice
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: PASS

- [ ] **Step 5: Add the `RewardedAdPresenting` seam**

Create `SwiftUp/Features/DailyQuiz/RewardedAdPresenting.swift`:

```swift
import Foundation

/// Gate for showing an ad before an optional, non-essential action — currently only the
/// past-editions practice redo (`TodayFlowView.startReplay`). Deliberately not tied to any ad SDK:
/// swapping in a real rewarded-ad implementation later means adding one new conforming type and
/// constructing `TodayFlowView` with it — nothing about the redo flow itself changes.
protocol RewardedAdPresenting {
    /// `completion(true)` if the ad played (or there was nothing to block on) and the gated action
    /// should proceed; `completion(false)` to abandon it (e.g. the user backed out of the ad).
    func presentAd(completion: @escaping (Bool) -> Void)
}

/// Today's stand-in — always proceeds immediately. No ad SDK is integrated yet.
struct NoOpAdPresenter: RewardedAdPresenting {
    func presentAd(completion: @escaping (Bool) -> Void) {
        completion(true)
    }
}
```

- [ ] **Step 6: Regenerate the Xcode project and build**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add SwiftUp/Features/DailyQuiz/QuizSession.swift SwiftUp/Features/DailyQuiz/RewardedAdPresenting.swift SwiftUpTests/RepositoryTests.swift
git commit -m "Add QuizSession.isPractice flag and RewardedAdPresenting ad seam"
```

---

## Task 3: `QuizEditionsView` + `TodayFlowView` wiring

**Files:**
- Create: `SwiftUp/Features/DailyQuiz/QuizEditionsView.swift`
- Modify: `SwiftUp/Features/DailyQuiz/TodayFlowView.swift`

**Interfaces:**
- Consumes: `ProfileRepository.lastSevenDays`, `ProfileRepository.profile.streakDays` (existing), `QuestionRepository.editionNumber` (existing), `QuestionRepository.effectiveLevel`, `QuestionRepository.fetchPastQuiz(for:)` (Task 1); `QuizSession.init(questions:isPractice:)` (Task 2); `RewardedAdPresenting`/`NoOpAdPresenter` (Task 2); `DailyEdition.weekdayName(for:)`/`shortWeekdayName(for:)` (Task 1); design-system atoms `RuledMasthead`, `EyebrowLabel`, `PlateNumeral` (all existing, in `SwiftUp/DesignSystem/`).
- Produces: `QuizEditionsView(todayXPEarned: Int, onSelectDay: (String) -> Void, onDoneForToday: () -> Void)` — a standalone, previewable SwiftUI view with no other dependents.

- [ ] **Step 1: Create `QuizEditionsView`**

Create `SwiftUp/Features/DailyQuiz/QuizEditionsView.swift`:

```swift
import SwiftUI

/// Shown after `QuizSummaryView`'s "Done"/"Review misses" — the hub between finishing today's real
/// quiz and (optionally) redoing an earlier day for practice. A redo picked here never touches XP,
/// accuracy, or streak (see `QuizSession.isPractice`'s doc comment for why that's structurally true,
/// not just a convention followed here).
struct QuizEditionsView: View {
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(QuestionRepository.self) private var questionRepo
    let todayXPEarned: Int
    let onSelectDay: (String) -> Void
    let onDoneForToday: () -> Void
    @State private var selectedDate: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: "\(editionLabel) · filed", right: DailyEdition.dateLabel())

                VStack(alignment: .leading, spacing: 12) {
                    EyebrowLabel("Today", color: Theme.Colors.accent700)
                    Text("That's today put to bed.")
                        .font(Theme.Fonts.heading(34))
                }
                .padding(.top, 30)

                HStack(alignment: .bottom, spacing: 30) {
                    VStack(alignment: .leading, spacing: 10) {
                        EyebrowLabel("Streak")
                        PlateNumeral("\(profileRepo.profile.streakDays)", font: Theme.Fonts.heading(64))
                        Text("days running")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.neutral600)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        EyebrowLabel("Earned")
                        Text("+\(todayXPEarned) xp today")
                            .font(Theme.Fonts.heading(22))
                            .foregroundStyle(Theme.Colors.accent700)
                    }
                }
                .padding(.top, 26)

                Text("Want more reps? Redo any open day from the last week for practice — it's just for you.")
                    .font(Theme.Fonts.body(15))
                    .foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 24)

                HStack {
                    EyebrowLabel("Back editions")
                    Spacer()
                    EyebrowLabel("\(openCount) open")
                }
                .padding(.top, 30)

                HStack(spacing: 8) {
                    ForEach(Array(profileRepo.lastSevenDays.enumerated()), id: \.offset) { index, entry in
                        dayBlock(entry, isToday: index == profileRepo.lastSevenDays.count - 1)
                    }
                }
                .padding(.top, 12)

                HStack(spacing: 14) {
                    legendItem("sat", color: Theme.Colors.text)
                    legendItem("open to sit", color: Theme.Colors.neutral200)
                    legendItem("today", color: Theme.Colors.accent)
                }
                .padding(.top, 14)

                if let oldest = profileRepo.lastSevenDays.first {
                    Text("\(DailyEdition.weekdayName(for: oldest.date)) closes tonight.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.neutral600)
                        .padding(.top, 12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    EyebrowLabel("What a redo is worth")
                    Text("0 xp · doesn't count toward accuracy · doesn't repair your streak")
                        .font(Theme.Fonts.body(14))
                        .foregroundStyle(Theme.Colors.neutral700)
                }
                .padding(.top, 26)

                HStack(spacing: 12) {
                    Button(action: onDoneForToday) {
                        Text("Done for today")
                            .font(.system(size: 16))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))

                    if let selectedDate {
                        Button(action: { onSelectDay(selectedDate) }) {
                            Text("Sit \(DailyEdition.weekdayName(for: selectedDate))'s")
                                .font(.system(size: 16))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .background(Theme.Colors.accent)
                        .foregroundStyle(Theme.Colors.bg)
                    }
                }
                .padding(.top, 30)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }

    private var editionLabel: String {
        questionRepo.editionNumber.map { "Edition \($0)" } ?? "Edition —"
    }

    /// Days in the window that are still open to redo — excludes today (never selectable) and any
    /// day already sat (`.done`/`.freeze`).
    private var openCount: Int {
        let days = profileRepo.lastSevenDays
        guard days.count > 1 else { return 0 }
        return days.dropLast().filter { $0.state == .missed }.count
    }

    @ViewBuilder
    private func dayBlock(_ entry: (date: String, state: StreakDayState), isToday: Bool) -> some View {
        let isOpen = !isToday && entry.state == .missed
        let isSelected = selectedDate == entry.date
        let fill: Color = isToday ? Theme.Colors.accent : (isOpen ? Theme.Colors.neutral200 : Theme.Colors.text)
        let foreground: Color = (isToday || !isOpen) ? Theme.Colors.bg : Theme.Colors.text

        VStack(spacing: 6) {
            Text(DailyEdition.shortWeekdayName(for: entry.date))
                .font(.system(size: 11, weight: .semibold))
            Text(isToday ? "today" : (isOpen ? "open to sit" : "sat"))
                .font(.system(size: 9))
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .foregroundStyle(foreground)
        .background(fill)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(isSelected ? Theme.Colors.accent700 : Theme.Colors.divider, lineWidth: isSelected ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture {
            guard isOpen else { return }
            selectedDate = isSelected ? nil : entry.date
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOpen ? .isButton : [])
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            EyebrowLabel(label)
        }
    }
}

#Preview {
    QuizEditionsView(todayXPEarned: 95, onSelectDay: { _ in }, onDoneForToday: {})
        .environment(ProfileRepository.preview())
        .environment(QuestionRepository.preview())
}
```

- [ ] **Step 2: Regenerate the Xcode project and build to verify the new view compiles standalone**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED. (`QuizEditionsView` isn't referenced anywhere yet, so this only checks it compiles in isolation.)

- [ ] **Step 3: Wire `TodayFlowView`'s new `.editions` stage and practice routing**

In `SwiftUp/Features/DailyQuiz/TodayFlowView.swift`, replace the whole file with:

```swift
import SwiftUI

struct TodayFlowView: View {
    enum Stage { case entry, question, summary, editions }

    @Environment(QuestionRepository.self) private var questionRepo
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(AuthRepository.self) private var authRepo
    @State private var stage: Stage = .entry
    @State private var session: QuizSession?          // today's real quiz — unchanged meaning
    @State private var practiceSession: QuizSession?   // a redo in progress, if any
    var adPresenter: RewardedAdPresenting = NoOpAdPresenter()

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
                        if let practiceSession {
                            QuizQuestionView(session: practiceSession, onAdvance: advancePractice)
                        } else if let session {
                            QuizQuestionView(session: session, onAdvance: advance)
                        }
                    case .summary:
                        if let session {
                            QuizSummaryView(session: session, onDone: { stage = .editions })
                        }
                    case .editions:
                        QuizEditionsView(
                            todayXPEarned: session?.totalXPEarned ?? 0,
                            onSelectDay: startReplay,
                            onDoneForToday: finish
                        )
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
            recordCompletion()
        }
    }

    /// Fired the moment the fifth question is answered, not when the user later dismisses the
    /// summary screen — so XP/streak are written to Firestore even if the user backgrounds or
    /// force-quits the app while looking at the summary, instead of only on a "Done" tap they
    /// might never make. Only ever runs for `session` (today's real quiz) — `practiceSession`
    /// never reaches this method (see `advancePractice`).
    private func recordCompletion() {
        guard let session, let uid = authRepo.currentUser?.uid else { return }
        Task { await questionRepo.recordAnswered(session.questions, for: uid) }
        Task { await profileRepo.recordCompletion(session, for: uid) }
    }

    /// Starts a practice redo of `dateKey`, gated on the ad seam. A `nil` past quiz (the date was
    /// never seeded) or a declined ad both quietly no-op — `stage` stays `.editions`, matching the
    /// spec's "no error UI for either case" (design §9).
    private func startReplay(for dateKey: String) {
        adPresenter.presentAd { completed in
            guard completed else { return }
            Task {
                guard let doc = await questionRepo.fetchPastQuiz(for: dateKey) else { return }
                practiceSession = QuizSession(
                    questions: doc.questions(for: questionRepo.effectiveLevel), isPractice: true
                )
                stage = .question
            }
        }
    }

    /// The practice-redo counterpart to `advance()` — deliberately never calls `recordCompletion()`
    /// or shows a summary screen: a redo's result is not persisted anywhere and does not affect XP,
    /// accuracy, or streak (see `QuizSession.isPractice`'s doc comment).
    private func advancePractice() {
        practiceSession?.advance()
        if practiceSession?.isFinished == true {
            practiceSession = nil
            stage = .editions
        }
    }

    private func finish() {
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

- [ ] **Step 4: Regenerate the Xcode project and build**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run the full test suite**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
Expected: All tests PASS, including every test added in Tasks 1-2.

- [ ] **Step 6: Manual verification in the simulator**

Launch the app in the iPhone 16 (OS 18.6) simulator, sign in, and walk through:
1. Finish today's daily quiz (answer all 5 questions) → confirm you land on the new "That's today put to bed." editions screen (not back at the entry screen).
2. Confirm the streak number and "+N xp today" shown match what `QuizSummaryView` just showed.
3. Confirm today's own day-block reads "today" and is not tappable; confirm at least one earlier day reads "open to sit" and is tappable (a day with no `dailyCompletions` entry — freshly-seeded test accounts have all 7 open).
4. Tap an open day, confirm the "Sit <Weekday>'s" button appears, tap it, confirm a 5-question quiz starts immediately (no ad — `NoOpAdPresenter` proceeds instantly).
5. Finish that redo quiz → confirm you land back on the editions screen (not the summary screen), and confirm the streak number and XP total are unchanged from before the redo.
6. Tap "Done for today" → confirm you return to the normal entry screen.
7. Confirm a day already sat (`.done`/`.freeze`) is not tappable and reads "sat".

Report any mismatch before proceeding — this is the only end-to-end check this feature gets (no Firestore emulator in this project).

- [ ] **Step 7: Commit**

```bash
git add SwiftUp/Features/DailyQuiz/QuizEditionsView.swift SwiftUp/Features/DailyQuiz/TodayFlowView.swift
git commit -m "Add past-editions redo screen and wire it into the daily quiz flow"
```
