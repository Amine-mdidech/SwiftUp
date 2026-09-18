# Path — Gameplay Loop (Sub-project C) — Design

Source design: Claude Design project "SwiftUP" (`SwiftUp Daily Quiz.dc.html`), turns `t13`–`t15` (the same source as Sub-projects A and B). Builds directly on Sub-project A (`docs/superpowers/specs/2026-09-18-path-foundation-design.md`) and Sub-project B (`docs/superpowers/specs/2026-09-18-path-navigation-design.md`), both merged: `SkillLevel` (4 grades), `PathTrack`/`PathStage`, `PathRepository`, and the three navigation screens (`PathWheelView`, `TrackLadderView`, `FourGradesView`).

## 0. Scope

This is the last of the three planned sub-projects. It builds the entire remaining gameplay loop: spending XP to unlock a stage → a linear slide deck (lesson stages only) → a quiz → an 80%-to-pass gate → the stage closes → a track closes once all its stages are closed → once every track in a grade is closed, a free regrade quiz unlocks → passing it promotes `SkillLevel` to the next grade.

Confirmed with the user during brainstorming:
- Lesson content is a linear slide deck (concept + example + detail, paged Next/Back), not a flip-card/self-rate mechanic — distinct from Interview Prep's `FlashcardSessionView`.
- Content (slides + quiz questions) is generated, formulaic placeholder text — same "structure real, content placeholder" principle Sub-project A used for track titles/costs. Real educational authoring stays deferred indefinitely.
- Spending XP on a stage is a one-time unlock. A failed quiz attempt can always be retried for free — no re-charge, ever, for the same stage.
- Track-assessment stages (`PathStage.Kind.assessment`) skip the slide deck entirely and go straight to a (larger) quiz.
- 80% is the pass bar everywhere: lesson-stage quizzes, track-assessment quizzes, and the regrade quiz — one consistent rule.
- Passing any quiz grants **no XP** — Path only ever spends `xpBalance` (earned elsewhere, via Daily Quiz / Interview Prep). Progress itself (unlocking further tracks, eventual promotion) is the only reward.
- The regrade quiz is free to start — closing every track in the grade is itself the unlock condition, no additional `xpCost`.
- The regrade quiz's entry point replaces the wheel for that grade (mirroring the existing Distinguished top-grade terminal state), not a banner elsewhere.

## 1. New data model

New file `SwiftUp/Models/PathContent.swift`:

```swift
import Foundation

struct PathSlide: Codable, Identifiable {
    let id: String
    let order: Int
    let title: String
    let body: String
    let example: String?   // nil-able: not every slide needs a code/example block
}

struct PathQuizQuestion: Codable, Identifiable {
    let id: String
    let prompt: String
    let options: [QuestionOption]   // reuses QuestionOption(id, text) from Question.swift
    let correctOptionID: String
}

struct PathStageContent: Codable {
    let stageID: String
    let slides: [PathSlide]     // empty for assessment stages
    let quiz: [PathQuizQuestion]
}

struct PathRegradeQuiz: Codable {
    let grade: SkillLevel       // the grade being graduated FROM
    let questions: [PathQuizQuestion]
}
```

`PathQuizQuestion` deliberately carries no `xp`, `topic`, `level`, or `format` field — Path's quizzes are pass/fail only and don't need `Question`'s Daily-Quiz-specific shape (confirmed during brainstorming: a new dedicated type, not an extension of `Question`/`QuizSession`).

## 2. Firestore schema, content generation, bundled fallback

**Two new collections**, mirroring `pathTracks`'s existing convention exactly:
- `pathStageContent/{stageId}` — one document per stage (141 total, matching Sub-project A's generated track/stage count), shape matches `PathStageContent`.
- `pathRegradeQuizzes/{grade}` — one document per grade that has a `.next` (`junior`, `mid`, `senior` — 3 documents; `distinguished` has none, it's terminal), shape matches `PathRegradeQuiz`, keyed by the grade's lowercased raw value (e.g. `junior`, matching `pathTracks`' `trackId` lowercasing convention).

**Generation script**, `scripts/generate_path_content.py` (sibling to `generate_path_tracks.py`): reads `scripts/path-tracks.json` (produced by Sub-project A's script — already checked in) to enumerate every stage's `id`/`title`/`kind` and every track's `grade`, and writes `scripts/path-content.json` as `{"stageContent": [...], "regradeQuizzes": [...]}`.

- **Lesson stage** (`kind == "lesson"`) → 4 slides, titled `"<stage title> — part N of 4"` (N = 1...4), with a formulaic `body` sentence naming the stage and its parent track (e.g. `"This part of {stage title} continues the {track title} track."`), and a formulaic `example` string on slides 2 and 4 only (`nil` on slides 1 and 3) — so the placeholder-ness stays honest rather than pretending every slide has a real code sample. Plus a 5-question quiz.
- **Assessment stage** (`kind == "assessment"`) → 0 slides, an 8-question quiz ("covers the whole track").
- **Regrade quiz** — one per grade with a `.next` (`junior`, `mid`, `senior`) → a 10-question quiz.

**Quiz questions are obviously placeholder, not fake-precise**: every question has exactly 4 options, literally labeled `"Correct answer"`, `"Incorrect answer 1"`, `"Incorrect answer 2"`, `"Incorrect answer 3"`. Their on-screen order is shuffled, deterministically seeded from `stageID` (or grade, for regrade quizzes) + question index, so generation is reproducible run-to-run. `correctOptionID` always points at the "Correct answer" option regardless of its shuffled position. This mirrors Sub-project A's own stated principle ("the placeholder nature is explicit and consistent rather than invented-but-pretend-precise") while keeping the whole loop genuinely playable end-to-end — a real user can read and pick the right answer without the app pretending to teach real material.

**Bundled fallback**, same three-copy convention already established for `path_tracks.json`: `scripts/path-content.json` → `SwiftUp/Resources/path_content.json` (app bundle) → `SwiftUpTests/Fixtures/path_content.json` (test fixture).

`scripts/seed_path_content.py` loads `scripts/path-content.json` and writes each stage-content doc to `pathStageContent/{stageID}` and each regrade quiz to `pathRegradeQuizzes/{grade}`, following `scripts/seed_path_tracks.py`'s exact structure (service-account-key check, one `set()` per document, idempotent, same error messaging). Not run against live Firestore during implementation — deferred pending explicit user authorization, same as every other seed script this session.

**Firestore rules**: both new collections get the same read-only pattern already used for `pathTracks` — `allow read: if request.auth != null; allow write: if false;`. Called out explicitly in this spec because a missing rule for `pathTracks` was the one Critical bug caught in Sub-project A's final review; this sub-project's plan must not repeat it.

## 3. User progress and XP spend

**New user-document field**: `startedPathStageIDs: [String: Timestamp]` — same shape and convention as the existing `completedPathStageIDs`. Marks a stage as "paid for, in progress," so a retry after a failed quiz never re-charges.

**`PathRepository.startStage(_ stage: PathStage, cost: Int, for uid: String) async -> SpendResult`**, where:
```swift
enum SpendResult {
    case started(newBalance: Int)
    case alreadyStarted   // stage already in startedPathStageIDs — retry, no charge
    case insufficientXP(balance: Int)
}
```
1. If the stage's id is already in `completedStageIDs` or the repository's own `startedStageIDs`, return `.alreadyStarted` immediately (no Firestore round trip needed for a stage already known to be unlocked).
2. Otherwise, read `users/{uid}.xpBalance` fresh from Firestore (not the possibly-stale local mirror — this is the one check that must reflect the true current balance).
3. If `xpBalance < cost` → return `.insufficientXP(balance:)`. Nothing is written.
4. Otherwise, one Firestore batch: decrement `xpBalance` by `cost`, add the stage's id to `startedPathStageIDs`. Commit, then update the repository's local `startedStageIDs` set and return `.started(newBalance:)`.

Called from `TrackLadderView`'s "Spend N xp · start stage M" button (currently a real, styled, but inert `{}` closure per Sub-project B's global constraint — this sub-project wires the real action). On `.started`/`.alreadyStarted`, the view navigates into the stage's content (slides for a lesson stage, straight to the quiz for an assessment stage). On `.insufficientXP`, the view shows an alert and does not navigate.

**Syncing `ProfileRepository`'s local mirror**: `ProfileRepository` gains a small method, `applyExternalXPBalance(_ newBalance: Int)`, that just updates the in-memory `profile.xpBalance` (a copy-with, no Firestore write — the write already happened in `PathRepository.startStage`). The view calls this after a successful `.started` result, avoiding a full `ProfileRepository.load` round trip while keeping every screen that displays `xpBalance` (e.g. the Profile masthead) live.

**Stage completion**: `PathRepository.completeStage(_ stage: PathStage, for uid: String) async` — one write, adding the stage's id to `completedPathStageIDs`. Called after a passing quiz attempt (≥80%). No XP write of any kind (confirmed: pure cost, no reward). `PathRepository.isTrackClosed` (Sub-project A, unchanged) already reflects the new completion on next check.

## 4. Stage flow: slides → quiz → result

New file `SwiftUp/Features/Path/PathLessonSession.swift`:
```swift
@Observable
final class PathLessonSession {
    let slides: [PathSlide]
    private(set) var currentIndex = 0

    init(slides: [PathSlide]) { self.slides = slides }

    var currentSlide: PathSlide? {
        guard currentIndex < slides.count else { return nil }
        return slides[currentIndex]
    }
    var isFinished: Bool { currentIndex >= slides.count }
    var isFirstSlide: Bool { currentIndex == 0 }
    var isLastSlide: Bool { currentIndex == slides.count - 1 }

    func advance() { currentIndex = min(currentIndex + 1, slides.count) }
    func goBack() { currentIndex = max(currentIndex - 1, 0) }
}
```

New file `SwiftUp/Features/Path/PathStageSlidesView.swift`: progress ticks (reusing the visual pattern from `FlashcardSessionView.progressTicks`), the current slide's title/body/optional example card, and a Back/Next footer. "Back" is disabled on the first slide. On the last slide, "Next" reads "Start the quiz" and pushes `PathQuizView` fed this stage's `quiz` array and a completion callback that calls `PathRepository.completeStage`.

New file `SwiftUp/Features/Path/PathQuizSession.swift`:
```swift
@Observable
final class PathQuizSession {
    let questions: [PathQuizQuestion]
    private(set) var currentIndex = 0
    private var answers: [String: String] = [:]

    init(questions: [PathQuizQuestion]) { self.questions = questions }

    var currentQuestion: PathQuizQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }
    var isFinished: Bool { currentIndex >= questions.count }
    var correctCount: Int {
        questions.filter { answers[$0.id] == $0.correctOptionID }.count
    }
    var scorePercent: Int {
        questions.isEmpty ? 0 : (correctCount * 100) / questions.count
    }
    var passed: Bool { scorePercent >= 80 }

    func selectedOptionID(for question: PathQuizQuestion) -> String? { answers[question.id] }
    func isAnswered(_ question: PathQuizQuestion) -> Bool { answers[question.id] != nil }
    func selectOption(_ optionID: String) {
        guard let question = currentQuestion, answers[question.id] == nil else { return }
        answers[question.id] = optionID
    }
    func advance() { currentIndex += 1 }
    func retry() { currentIndex = 0; answers = [:] }
}
```

New file `SwiftUp/Features/Path/PathQuizView.swift`: takes a `title: String` (the stage or track title, or "Regrade quiz" for §6), a `PathQuizSession`, and an `onPassed: () async -> Void` callback. Presents one question per screen (same visual shape as `QuizQuestionView`, minus any XP display) with a progress indicator ("Question X of Y"). On `isFinished`, shows a result screen: score (`"N of M correct — P%"`), pass/fail banner, and:
- **Pass** → calls `onPassed()` (which the caller wires to `PathRepository.completeStage` for a stage quiz, or `PathRepository.promoteGrade` for the regrade quiz — see §6), then a "Back to <context>" button that pops the navigation stack.
- **Fail** → a "Try again" button that calls `session.retry()` and re-renders the first question — free retry, no re-navigation, no re-spend, per the confirmed retry economy.

This one `PathQuizView`/`PathQuizSession` pair is reused verbatim for a lesson stage's quiz (after slides), a track-assessment stage's quiz (no slides), and the regrade quiz — only the question array, title, and `onPassed` callback differ.

## 5. Track-assessment stage

Mechanically identical to a lesson stage's spend flow. The one difference: `TrackLadderView`'s stage-tap handler checks `stage.kind` — a `.lesson` stage pushes `PathStageSlidesView`; an `.assessment` stage pushes `PathQuizView` directly (skipping the slide deck entirely, per the confirmed design). Same spend/retry/completion rules apply unchanged. Closing the assessment stage closes the track, since it's already the track's final stage under Sub-project A's existing `isTrackClosed` logic — no new "track closed" event needs to be separately detected or written.

## 6. Regrade quiz and promotion

**Trigger point**: `PathWheelView` gains a third top-level state, alongside its existing "normal wheel" and "Distinguished terminal" states:
```
if pathRepo.grade == .distinguished && isAtTopGrade { topGradeContent }        // existing, unchanged
else if pathRepo.grade != .distinguished && allCurrentGradeTracksClosed { readyToRegradeContent }   // new
else { wheelContent }                                                          // existing, unchanged
```
where `allCurrentGradeTracksClosed` is `!currentGradeTracks.isEmpty && currentGradeTracks.allSatisfy(pathRepo.isTrackClosed)` — the same predicate shape `isAtTopGrade` already uses, just without the `.distinguished` grade check.

`readyToRegradeContent` is a new view section, visually in the same family as the existing top-grade terminal state (a congratulatory header, this grade's closed tracks listed) plus a "Start the regrade quiz" button pushing `PathRegradeQuizView`. No XP cost or check — closing every track is itself the unlock (confirmed).

New file `SwiftUp/Features/Path/PathRegradeQuizView.swift`: thin wrapper around `PathQuizView`, constructed with the current grade's `PathRegradeQuiz.questions`, title `"Regrade quiz"`, and `onPassed` wired to:
```swift
func promoteGrade(from grade: SkillLevel, for uid: String) async {
    guard let next = grade.next else { return }
    // one Firestore write: users/{uid}.skillLevel = next.rawValue
    // then update the repository's local `grade` to `next` immediately — no reload needed
}
```
on `PathRepository`. After promotion, popping back to `PathWheelView` re-evaluates the three-way state above against the *new* `pathRepo.grade` — showing the new grade's normal wheel (or, in the edge case of promoting into Distinguished with zero Distinguished tracks yet closed, correctly the normal wheel rather than the terminal state, since `isAtTopGrade` requires all of Distinguished's own tracks closed too).

On fail: same free-retry pattern as any other quiz via `PathQuizView`'s "Try again" — no penalty, no re-check of anything.

This is the only place `SkillLevel` is written outside onboarding, fulfilling Sub-project A's stated intent that "Path's regrade becomes the only promotion path."

## 7. Testing

- `PathQuizSession`: `scorePercent`/`passed` at various correct/incorrect ratios, including the boundary (exactly 80% passes, 79% fails); `retry()` resets `currentIndex`/`answers` but keeps the same `questions` array (same instance, not re-fetched).
- `PathLessonSession`: `advance()`/`goBack()` bounds — can't go below slide 0 or past `slides.count`; `isFinished` exactly at `currentIndex == slides.count`.
- `PathRepository.startStage`: the insufficient-balance and already-started branches, tested as pure logic against hand-built state (no Firestore needed) — same style as `isTrackReachable`'s existing tests. The real Firestore batch-write branch isn't independently unit-tested, matching the accepted limitation already in place for every other Firestore write in this project.
- `PathStageContent`/`PathRegradeQuiz` decoding from the bundled fixture JSON: count checks (141 stage-content docs, 3 regrade quizzes), plus a content-integrity check that every quiz question's `correctOptionID` actually matches one of that question's own `options` — not just "does it decode."
- `PathRepository.isTrackClosed` after `completeStage`: a track with N-1 of N stages completed isn't closed; completing the Nth stage closes it. Extends Sub-project A's existing test rather than duplicating a new suite.
- `PathRepository.promoteGrade`: pure logic asserting the local `grade` updates to `.next` and that calling it on `.distinguished` (no `.next`) is a no-op.

## 8. Out of scope (explicitly deferred)

- Real authored slide/quiz content — still deferred indefinitely, per the user's original request.
- Any change to Daily Quiz or Interview Prep content/mechanics — this sub-project only adds new, fully decoupled types.
- Offline queuing or retry of a spend/completion write that fails mid-flight — same "non-blocking, best-effort" posture already accepted everywhere else in this codebase's Firestore writes.
- A "spend XP" undo/refund path — not asked for, not building it.
- Running `scripts/seed_path_content.py` against live Firestore — deferred pending explicit user authorization, same as every prior seed script this session.
