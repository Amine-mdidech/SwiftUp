# Daily Quiz — Past Editions Redo — Design

Source design: Claude Design project "Design prioritization inquiry" (`SwiftUp Daily Quiz.dc.html`), turn `t12`/`12a` ("After the daily quiz — replay an earlier day (follows 1f)").

## 1. Goal

Today, finishing the daily quiz (`QuizSummaryView`, "Done") drops the user straight back to `TodayFlowView`'s entry screen. This adds a screen in between: the user's streak, today's XP, and a row of the last 7 calendar days (today + 6 before it) they can pick from to redo that day's quiz for their own practice.

Confirmed with the user, both departing from the design mockup's stated copy:
- **Redoing a past day has zero effect on their stats** — no XP, no topic-accuracy credit, no streak change. The mockup says "full xp... counts toward accuracy... no streak repair"; the actual behavior here is "none of the above, purely practice." The screen's own copy is written to match this real behavior, not the mockup's.
- **No "longest streak ever" tracking is added.** The mockup's "Longest yet" line is dropped; the screen shows only the current streak count and today's XP.

Also confirmed: an ad is *meant* to play before a redo starts, but isn't built yet — this pass adds a clean, swappable seam for that, not an ad integration.

## 2. Data model

**No new Firestore fields, no new collections, no new writes.** A practice redo never calls `ProfileRepository.recordCompletion` or `QuestionRepository.recordAnswered` — "zero impact" is achieved by simply not running the code that has any impact, not by adding conditionals inside methods that already have a lot of side effects (spec author's note: `recordCompletion` alone touches XP, streak, freezes, topicStats, perfectDayCount, achievements, `lastCompletedDate`, `dailyCompletions/{today}`, a possible frozen-day write, and the leaderboard entry — see §7 for exactly which call sites a practice session must never reach).

The "last 7 days" picker reuses `dailyCompletions/{date}` presence/shape and the `StreakDayState`/`streakDayRecords` machinery already built for the 16-week streak calendar — no new read path.

## 3. `QuestionRepository` — fetching a past day's quiz

`load(for uid:)` already computes an `effectiveLevel` local variable to pick `todayQuestions` from `dailyQuizzes/{today}`, but never stores it — nothing else can currently ask "what level is this user's quiz at." Store it:

```swift
private(set) var effectiveLevel: SkillLevel = .junior
```

set at the same place `todayQuestions`/`editionNumber` are set, at the end of `load(for uid:)`:

```swift
todayQuestions = daily.questions(for: effectiveLevel)
editionNumber = daily.edition
self.effectiveLevel = effectiveLevel   // NEW — the only line added to load(for:)
```

New method, parameterizing the existing today-only fetch (no promotion check — that only matters for the user's *current* quiz, not a historical replay):

```swift
/// A past date's shared daily quiz, for replay/practice — same document shape as today's, just a
/// different `dailyQuizzes/{date}` key. `nil` if that date was never seeded (predates the app, or
/// fell outside the seed script's rolling window) — the caller treats this as "nothing to replay."
func fetchPastQuiz(for dateKey: String) async -> DailyQuizDocument? {
    try? await Firestore.firestore()
        .collection("dailyQuizzes").document(dateKey)
        .getDocument(as: DailyQuizDocument.self)
}
```

Caller picks the array with `doc.questions(for: questionRepo.effectiveLevel)` — the same level the user's real quiz today was drawn from.

## 4. `ProfileRepository` — the 7-day window

`buildCalendarDays` already computes "the last N calendar dates ending today" internally (hardcoded to 112) to build `streakCalendarDays`. Factor the date-listing out so a 7-day window can reuse it instead of duplicating the offset arithmetic:

```swift
private static func recentDates(before today: String, count: Int) -> [String] {
    (0..<count).compactMap { offset in StreakCalculator.dateOffset(-(count - 1 - offset), from: today) }
}

static func buildCalendarDays(from records: [String: StreakDayState], today: String) -> [StreakDayState] {
    recentDates(before: today, count: 112).map { records[$0] ?? .missed }
}
```
(`buildCalendarDays`'s own signature, behavior, and existing tests are unchanged — this is purely an internal refactor.)

New computed property:

```swift
/// Today + the 6 days before it, oldest first, today last — for the post-quiz "redo an earlier
/// day" picker. Unlike `streakCalendarDays`, callers need the date string itself (to know which
/// day a tap means), not just its state.
var lastSevenDays: [(date: String, state: StreakDayState)] {
    let today = Self.todayString()
    return Self.recentDates(before: today, count: 7).map { ($0, streakDayRecords[$0] ?? .missed) }
}
```

The design's three visual states map onto the existing three `StreakDayState` cases plus "is this today": `.done` or `.freeze` → "sat" (ink fill — a redo isn't offered for a day already on record, frozen or not); `.missed` → "open to sit" (outlined); the last entry (today) is always rendered as "today" regardless of its `StreakDayState`, and is not selectable.

## 5. `QuizSession` — one additive flag

```swift
let isPractice: Bool

init(questions: [Question], isPractice: Bool = false) {
    self.questions = questions
    self.isPractice = isPractice
}
```
Default `false` — every existing call site (today's real quiz, plus `#Preview`s) is unaffected.

## 6. The ad seam

```swift
protocol RewardedAdPresenting {
    /// `completion(true)` if the ad played (or there was nothing to block on); `completion(false)`
    /// to abandon starting the replay (e.g. the user backed out of the ad).
    func presentAd(completion: @escaping (Bool) -> Void)
}

/// Today's stand-in — always proceeds immediately. Swapping in a real ad SDK later means replacing
/// this one type where `TodayFlowView` is constructed; nothing about the redo flow itself changes.
struct NoOpAdPresenter: RewardedAdPresenting {
    func presentAd(completion: @escaping (Bool) -> Void) { completion(true) }
}
```

`TodayFlowView` gains a plain (non-`@State`, stateless dependency) property `var adPresenter: RewardedAdPresenting = NoOpAdPresenter()`.

## 7. `TodayFlowView` — the new stage and practice routing

Add `.editions` to `Stage`. Add a second session slot so the real quiz's result (for today's XP display) survives switching into a practice session:

```swift
enum Stage { case entry, question, summary, editions }
...
@State private var session: QuizSession?          // today's real quiz — unchanged meaning
@State private var practiceSession: QuizSession?   // NEW — a redo in progress, if any
```

The `.question` case now shows whichever session is active:
```swift
case .question:
    if let practiceSession {
        QuizQuestionView(session: practiceSession, onAdvance: advancePractice)
    } else if let session {
        QuizQuestionView(session: session, onAdvance: advance)
    }
```
(`QuizQuestionView` itself needs no changes — it already only depends on a `QuizSession`, never "today" specifically.)

`QuizSummaryView`'s `onDone` now goes to `.editions` instead of calling the existing `finish()`:
```swift
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
```
`finish()` (existing: `session = nil; stage = .entry`) becomes reachable only from the editions screen's "Done for today" — its meaning doesn't change, just where it's called from.

New methods:
```swift
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

private func advancePractice() {
    practiceSession?.advance()
    if practiceSession?.isFinished == true {
        practiceSession = nil
        stage = .editions   // back to the hub — no summary screen, no recordCompletion
    }
}
```

The existing `advance()`/`recordCompletion()` (today's real quiz) are **untouched** — they only ever run for `session`, never `practiceSession`, so `isPractice` doesn't need to be checked inside them at all; the practice path simply never calls them.

## 8. New `QuizEditionsView`

New file `SwiftUp/Features/DailyQuiz/QuizEditionsView.swift`:

```swift
struct QuizEditionsView: View {
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(QuestionRepository.self) private var questionRepo
    let todayXPEarned: Int
    let onSelectDay: (String) -> Void
    let onDoneForToday: () -> Void
    @State private var selectedDate: String?

    var body: some View { ... }
}
```

Content, top to bottom (matching the design's `12a`, with the zero-impact copy substitution from §1):
- `RuledMasthead` — left: `"Edition \(questionRepo.editionNumber ?? …) · filed"`, right: today's date.
- Headline: "That's today put to bed."
- `PlateNumeral("\(profileRepo.profile.streakDays)")` + "days running" + `"+\(todayXPEarned) xp today"`.
- Body copy inviting a redo of one of the last 7 days.
- "Back editions" section header with an open-count (`lastSevenDays.filter { $0.state == .missed && it's not today }.count`).
- A row of 7 date blocks from `profileRepo.lastSevenDays`: the last entry (today) renders as the non-interactive "today" state; each other entry renders "sat" (ink, `.done`/`.freeze`) or "open to sit" (outlined, `.missed`) and is tappable when open, setting `selectedDate`.
- Legend row (3 swatches: sat / open to sit / today).
- Expiry line naming `lastSevenDays.first` (the oldest day in the window, the one that ages out tonight).
- The "what this is worth" 3-line key/value, rewritten per §1: **0 xp · doesn't count toward accuracy · doesn't repair your streak.**
- Footer: "Done for today" (secondary, always enabled, calls `onDoneForToday`) / a primary button labeled `"Sit \(weekday(selectedDate))'s"` when a day is selected (disabled/hidden when `selectedDate == nil`), calling `onSelectDay(selectedDate)`.

## 9. Error handling

`fetchPastQuiz` returning `nil` (date never seeded): `startReplay` simply does nothing further — `stage` stays `.editions`, no session is created. This is a quiet no-op rather than an error message, consistent with how a `.missed` day only appears as "open to sit" in the first place because a `dailyCompletions` doc doesn't exist for it — a genuinely absent `dailyQuizzes` doc for that same date is treated the same way (nothing to redo).

`adPresenter.presentAd` calling back with `false`: `startReplay` returns without starting anything — same as above, no error UI.

## 10. Testing

- `QuizSession(questions:isPractice:)`: default `isPractice == false`; explicit `true` is stored and readable.
- `ProfileRepository.lastSevenDays`: given a `streakDayRecords` dictionary with a mix of `.done`/`.freeze`/absent entries across a 7-day span, returns exactly 7 `(date, state)` pairs oldest-first-today-last, with absent dates as `.missed` — same style of pure/testable assertion as the existing `buildCalendarDays` tests, and confirms the `recentDates` refactor didn't change `buildCalendarDays`'s own behavior (existing tests must still pass unmodified).
- `QuestionRepository.effectiveLevel` and `fetchPastQuiz` touch Firestore and aren't unit-tested in this project (no emulator, same limitation as every other repository) — verified by manual run-through: finish today's quiz, land on the editions screen, redo an open day, confirm no XP/streak/topic-accuracy change and confirm the user is returned to the editions screen (not a summary) when the redo finishes.

## 11. Out of scope / open implementation decisions (flagged, not blocking)

- Exact wording/date-formatting for the expiry line ("Tuesday the 1st closes tonight") — implementation-time detail.
- What happens if `dailyCompletions/{today}` somehow already shows the current day as `.done` by the time this screen renders (it never does today, since a practice session can't write it, and the real session's own completion write also keys off `today` — included here only to note the case is definitionally unreachable, not something to special-case).
- The in-progress "replay" quiz screen itself has no dedicated design (the source design's own "Try next" list flags this as unbuilt) — reusing `QuizQuestionView` unmodified is this spec's explicit choice, not a placeholder.
- A real `RewardedAdPresenting` implementation — explicitly out of scope this pass; `NoOpAdPresenter` is the shipped behavior.
