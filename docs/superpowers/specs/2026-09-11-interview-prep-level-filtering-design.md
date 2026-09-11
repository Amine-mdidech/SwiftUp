# Interview Prep — Level-Aware Content & Real Hosting — Design

## 1. Goal

Today the Interview Prep tab's Junior/Mid/Senior `SegmentedPicker` only recolors the screen (`InterviewBankView.levelAccent`) — `levelFilter` is never used to filter anything. Tapping a category always opens `InterviewRepository.firstQuestion(in:)`, and "Next question" always calls `nextQuestion(after:)`; both walk every question in the category by `indexInCategory` regardless of `difficulty`. A user filtered to "Mid" today still gets Senior/Junior questions mixed in.

Underlying that bug is a second problem: the actual content is a 5-question bundled JSON stub (`SwiftUp/Resources/interview_questions.json`, one question per category, one per difficulty) while `interview_categories.json` claims totals like "31 of 36 reviewed" that don't correspond to any real bundled content — there is no path to grow this bank without shipping a new binary, and no real content exists yet.

This pass: (1) makes the level filter actually filter which questions a user sees, and (2) moves the question bank to Firestore, authored via a seed script, mirroring the `dailyQuizzes` pattern already proven in this codebase — so the bank can grow without app releases.

**Out of scope** (confirmed with user): making "Mark reviewed" real. That button is currently a no-op (`Button {} label: { Text("Mark reviewed") ... }`) and `reviewedCount` is static mock data disconnected from any actual review behavior. Wiring real per-user review tracking is a separate future pass. This design instead stops displaying `reviewedCount` as a fabricated number (§5) — the same call made for the profile screen's fake "Top 4% this week" in a prior pass.

## 2. Firestore schema

**New top-level collection `interviewBank/{categorySlug}`** — one document per category, public read-only content (not user data), shaped like `DailyQuizDocument`'s per-level arrays:

```
interviewBank/architecture-patterns = {
  name: "Architecture patterns",
  junior: [InterviewQuestion...],
  mid: [InterviewQuestion...],
  senior: [InterviewQuestion...]
}
```

`categorySlug` is a stable, human-assigned id (e.g. `architecture-patterns`) distinct from `name` — decouples the document key from display-text edits.

Each array element is an `InterviewQuestion` (schema below, §4) — no `indexInCategory`/`totalInCategory` stored: a question's position within its level is its array index, and the level's question count is the array length. This mirrors how `DailyQuizDocument`'s `Question` model carries no explicit ordinal either.

**Firestore rules** — same admin-authored, client-read-only shape as `dailyQuizzes`:

```
match /interviewBank/{categorySlug} {
  allow read: if request.auth != null;
  allow write: if false;
}
```

## 3. Content authoring

**New `scripts/interview-bank.json`** — the source of truth, git-tracked and human-editable, one entry per category:
```json
[
  {
    "slug": "architecture-patterns",
    "name": "Architecture patterns",
    "junior": [ /* InterviewQuestion objects, no id/index bookkeeping needed beyond a stable id */ ],
    "mid": [ ... ],
    "senior": [ ... ]
  },
  ...
]
```

**New `scripts/seed_interview_bank.py`**, mirroring `scripts/seed_daily_quizzes.py`'s structure and conventions:
- Reads `interview-bank.json`, writes one Firestore doc per category to `interviewBank/{slug}` via a batch.
- Full-overwrite per doc, safe to re-run (same "safe to re-run" contract as the daily-quiz seeder).
- Same `serviceAccountKey.json` setup story, same style of docstring/usage comment.

This replaces hand-maintaining `interview_questions.json`/`interview_categories.json` as the growth path: adding real content means editing `interview-bank.json` and re-running the seed script, no app release required.

## 4. Model changes

**`InterviewQuestion`** — drop `indexInCategory`/`totalInCategory`:
```swift
struct InterviewQuestion: Codable, Identifiable {
    let id: String
    let category: String
    let difficulty: String
    let prompt: String
    let modelAnswer: String
    let talkingPoints: [String]
    let followUps: [String]
    let bookmarked: Bool
}
```
`category`/`difficulty` stay as denormalized fields (redundant with which document/array a question was decoded from) because `InterviewQuestionDetailView` displays them directly and `nextQuestion(after:)` needs `question.difficulty` to know which level to keep walking (§6) — no separate level parameter needs to be threaded through navigation calls.

**New `InterviewCategoryContent`** (replaces `InterviewCategory` as what the repository holds internally):
```swift
struct InterviewCategoryContent: Decodable {
    let name: String
    let junior: [InterviewQuestion]
    let mid: [InterviewQuestion]
    let senior: [InterviewQuestion]

    func questions(for level: String?) -> [InterviewQuestion] {
        switch level {
        case "Junior": junior
        case "Mid": mid
        case "Senior": senior
        default: junior + mid + senior   // "All"
        }
    }
}
```
`InterviewBankView`'s existing `["All", "Junior", "Mid", "Senior"]` strings are used directly as the lookup key — no new enum introduced, matching how `question.difficulty` is already a plain `String` rather than an enum today (kept consistent rather than introducing a `SkillLevel`-style enum just for this pass — flagged as a possible future cleanup, §8).

## 5. `InterviewRepository` — read path

Rewritten to the same async/`@Observable` shape as `LeaderboardRepository`:
```swift
@Observable
final class InterviewRepository {
    private(set) var categories: [InterviewCategoryContent] = []
    private(set) var isLoading = false

    init() {}

    static func preview(bundle: Bundle = .main) -> InterviewRepository { ... }  // bundled fallback

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await Firestore.firestore().collection("interviewBank").getDocuments()
            categories = snapshot.documents.compactMap { try? $0.data(as: InterviewCategoryContent.self) }
        } catch {
            categories = Self.loadBundledFallback()
        }
    }

    static func loadBundledFallback(bundle: Bundle = .main) -> [InterviewCategoryContent] {
        decodeJSONResource([InterviewCategoryContent].self, filename: "interview_bank", bundle: bundle) ?? []
    }
}
```
No `uid` parameter — this content isn't gated on the signed-in user, only on being signed in at all (same as `questions`/`dailyQuizzes` rules). `RootView` continues constructing `InterviewRepository()` eagerly (unchanged), but loading moves out of `init` into `.task` on `InterviewBankView` (§6) — the bank isn't needed until the user opens that tab, same reasoning the leaderboard design applied to `LeaderboardView`.

`firstQuestion(in:)`/`nextQuestion(after:)` are replaced by level-aware equivalents:
```swift
func firstQuestion(in categoryName: String, level: String) -> InterviewQuestion?
func nextQuestion(after current: InterviewQuestion) -> InterviewQuestion?
```
- `firstQuestion(in:level:)`: finds the category by name, returns `questions(for: level).first`. For `level == "All"`, tries Junior → Mid → Senior in that order and returns the first non-empty level's first question (deterministic tie-break, since `questions(for: nil)` concatenates rather than interleaves — see §6 for why "All" needs its own path here rather than reusing the concatenation).
- `nextQuestion(after:)`: unchanged signature (no level parameter — inferred from `current.difficulty`, §4). Walks `current`'s own category+level array; on exhausting it, wraps to the next category's *same-level* array, skipping categories with zero questions at that level, same "wrap to next category" behavior the app has today just level-scoped. If no category has any question at that level (shouldn't happen since `current` itself proves at least one exists), returns `current`'s own array's first element (self-loop, matching today's existing wrap-to-self fallback when there's nowhere else to go).

## 6. `InterviewBankView` — filtering & empty state

- Add `.task { await repo.load() }` (no `uid` guard needed, §5).
- Per category, compute `count = category.questions(for: levelFilter == "All" ? nil : levelFilter).count`.
- If `count == 0` (whether the filter is a specific level, or "All" and every level is empty): row renders **disabled** — greyed text, no `NavigationLink`, progress bar replaced with "No \(levelFilter) questions yet" (confirmed with user; under "All" this reads as "No questions yet"). Still visible, just non-interactive, so the category list doesn't reflow/hide rows as the filter changes. This also closes the edge case where a category has zero content at every level — without it, that row would look tappable but silently do nothing, since `firstQuestion(in:level:)` has nothing to return.
- If `count > 0`: row navigates to `repo.firstQuestion(in: category.name, level: levelFilter)`.
- **`reviewedCount` is removed from the row entirely** — it was static mock data with no relationship to real review state (out of scope, §1). The progress bar's fill becomes purely presentational scaffolding removed for this pass rather than left showing a number that can no longer line up once `totalCount` becomes level-aware; re-introduced for real once review-tracking (§1, deferred) is designed. The row instead shows just the count for the active filter, e.g. "12 questions" (exact copy is an implementation-time wording choice, not a design decision, same flag style as the leaderboard spec).

## 7. `InterviewQuestionDetailView`

- "Question X of Y" changes from the old flat `question.indexInCategory`/`totalInCategory` fields (now removed, §4) to a value computed on demand by one new `InterviewRepository` method:
  ```swift
  func position(of question: InterviewQuestion) -> (index: Int, total: Int)? {
      guard let category = categories.first(where: { $0.name == question.category }) else { return nil }
      let levelQuestions = category.questions(for: question.difficulty)
      guard let idx = levelQuestions.firstIndex(where: { $0.id == question.id }) else { return nil }
      return (index: idx + 1, total: levelQuestions.count)
  }
  ```
  It finds `question`'s category, narrows to `question.difficulty`'s array via `InterviewCategoryContent.questions(for:)` (§4), and reports 1-based position within that array — kept as one repository method rather than duplicating the category/level lookup in the view.
- "Next question" button behavior is otherwise unchanged (`repo.nextQuestion(after: question)`), now level-scoped for free via §5.

## 8. Error handling

- `load()` Firestore failure (offline, first launch, not yet seeded): falls back to the bundled `interview_bank.json` fixture — same degrade path as `dailyQuizzes`/`leaderboardEntries`.
- A category present in Firestore with an empty array for some level is a normal, expected state while content is still being filled in (§6 disabled-row handling), not an error.

## 9. Testing

- Update `SwiftUpTests/Fixtures/interview_categories.json` + `interview_questions.json` (and the `Resources/` copies) to the new `interview_bank.json` per-category/per-level-array schema — same content, reshaped, so `interviewRepositoryFindsFirstAndNextQuestion` in `RepositoryTests.swift` keeps working with an updated shape.
- New unit tests for the pure logic (no Firestore, same style as `LeaderboardRankingTests`):
  - `firstQuestion(in:level:)` returns the right question for each explicit level, and the Junior→Mid→Senior tie-break for `"All"`.
  - `nextQuestion(after:)` stays within the current question's level, wraps to the next category at the same level, and skips a category with zero questions at that level while wrapping.
  - `InterviewCategoryContent.questions(for:)` count logic for each level and `nil`/"All".
- Firestore read itself isn't unit-testable (no emulator in this project, same limitation noted in the leaderboard spec) — verified by manual run-through once `interview-bank.json` is seeded to the real project.

## 10. Open implementation decisions (flagged, not blocking)

- Exact wording for the disabled-row "No {level} questions yet" state and the replacement count label (§6) — picked at implementation time.
- Whether `category`/`difficulty` ever graduate from plain `String` to enums (`SkillLevel` already exists for the daily quiz's Junior/Mid/Senior) — not done in this pass to keep the diff minimal against how `InterviewQuestion.difficulty` already reads today; worth revisiting if a third feature needs the same level concept.
- Real content volume/size for `interview-bank.json` is unknown (today's bundled set is a 5-question stub) — collection-of-small-docs (one per category) keeps any single document well under Firestore's 1MB cap regardless of how large the bank grows, so no resharding is anticipated.
